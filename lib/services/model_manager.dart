import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/ai_model_info.dart';
import '../models/download_state.dart';
import 'wakelock_service.dart';

/// Manages model catalog, downloads, and local file discovery.
class ModelManager extends GetxService {
  final catalog = <AiModelInfo>[].obs;
  final downloadedModels = <String>[].obs; // filenames on-disk (list for reactivity)
  
  // ── Download tracking (single reactive object) ─────────────
  final activeDownloads = <String, DownloadState>{}.obs;
  final tick = 0.obs; // force UI refresh counter

  late String _modelsDir;

  /// [modelsDirOverride] lets tests point the manager at a temp directory
  /// instead of the platform documents directory.
  Future<ModelManager> init({String? modelsDirOverride}) async {
    _modelsDir = modelsDirOverride ?? await _getModelsDir();
    if (modelsDirOverride != null) {
      await Directory(modelsDirOverride).create(recursive: true);
    }
    await _loadCatalog();
    await scanDownloaded();
    return this;
  }

  /// Resolve models directory.
  Future<String> _getModelsDir() async {
    // Only check USB path on desktop platforms
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        final execDir = Platform.resolvedExecutable;
        final usbShared = p.join(p.dirname(p.dirname(execDir)), 'Shared', 'models');
        if (await Directory(usbShared).exists()) {
          return usbShared;
        }
      } catch (_) {
        // Ignore errors resolving executable path
      }
    }

    // Fall back to app documents
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = p.join(appDir.path, 'PortableAI', 'models');
    await Directory(modelsDir).create(recursive: true);
    return modelsDir;
  }

  String get modelsDir => _modelsDir;

  /// Force all Obx listeners to rebuild.
  void _notifyUI() {
    tick.value++;
  }

  /// Load the embedded model catalog from assets + persisted custom models.
  Future<void> _loadCatalog() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/models_catalog.json');
      final list = jsonDecode(jsonStr) as List;
      catalog.value =
          list.map((j) => AiModelInfo.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      // Catalog couldn't load — will be empty
    }

    // Load persisted custom models
    try {
      final box = Hive.box('models_meta');
      final customList = box.get('custom_models', defaultValue: <dynamic>[]) as List;
      for (final raw in customList) {
        final model = AiModelInfo.fromJson(Map<String, dynamic>.from(raw as Map));
        // Don't add duplicates
        if (!catalog.any((m) => m.id == model.id)) {
          catalog.add(model);
        }
      }
    } catch (_) {}
  }

  /// Scan the models directory for downloaded .gguf files.
  Future<void> scanDownloaded() async {
    final dir = Directory(_modelsDir);
    if (!await dir.exists()) return;

    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.gguf'))
        .map((f) => p.basename(f.path))
        .toList();

    downloadedModels.value = files;
  }

  String getModelPath(AiModelInfo model) => p.join(_modelsDir, model.filename);
  String getModelPathByFilename(String filename) => p.join(_modelsDir, filename);
  bool isModelDownloaded(AiModelInfo model) => downloadedModels.contains(model.filename);

  /// Is this model currently downloading?
  bool isDownloading(String filename) {
    return activeDownloads.containsKey(filename) &&
        activeDownloads[filename]!.isActive;
  }

  /// Get the download state for a model (or null).
  DownloadState? getDownloadState(String filename) {
    return activeDownloads[filename];
  }

  /// Download a model with real-time speed tracking.
  ///
  /// Enables wake lock + foreground service to keep the download alive.
  /// Verifies the HTTP response before writing anything, and the file's
  /// checksum before publishing it under its final name.
  Future<void> downloadModel(AiModelInfo model) async {
    if (isDownloading(model.filename)) return;

    // Enable wake lock + foreground service for download (fire and forget so UI updates instantly)
    WakelockService? wakelockService;
    try {
      wakelockService = Get.find<WakelockService>();
      wakelockService.enableForDownload(modelName: model.name);
    } catch (e) {
      debugPrint('WakelockService not available: $e');
    }

    // Initialize download state instantly
    final state = DownloadState(
      filename: model.filename,
      totalBytes: model.sizeGb * 1024 * 1024 * 1024,
    );
    activeDownloads[model.filename] = state;
    _notifyUI();

    final filePath = getModelPath(model);
    final partFile = File('$filePath.part');

    // Each download owns its client. A single shared field meant cancelling
    // or finishing one transfer tore down every other transfer's connection.
    final client = http.Client();
    state.client = client;

    try {
      final request = http.Request('GET', Uri.parse(model.url));

      // Support resume
      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }
      }

      final response = await client.send(request);

      _assertDownloadable(response, model);

      // A server may ignore Range and reply 200 with the whole body. Appending
      // that to an existing partial produces a corrupt file that is larger than
      // the real model, so fall back to a clean restart instead.
      var resuming = existingBytes > 0;
      if (resuming && response.statusCode != HttpStatus.partialContent) {
        resuming = false;
        existingBytes = 0;
      }

      final contentLength = response.contentLength ?? 0;
      final totalBytes = (existingBytes + contentLength).toDouble();

      state.totalBytes = totalBytes > 0 ? totalBytes : state.totalBytes;
      state.receivedBytes = existingBytes.toDouble();

      final sink = partFile.openWrite(
          mode: resuming ? FileMode.append : FileMode.write);

      int receivedBytes = existingBytes;
      final stopwatch = Stopwatch()..start();
      int lastSpeedCheck = 0;
      int lastSpeedBytes = existingBytes;

      try {
        await for (final chunk in response.stream) {
          // Check if cancelled
          if (state.isCancelled) break;

          sink.add(chunk);
          receivedBytes += chunk.length;
          state.receivedBytes = receivedBytes.toDouble();

          // Calculate speed every 500ms
          if (stopwatch.elapsedMilliseconds - lastSpeedCheck > 500) {
            final elapsed = (stopwatch.elapsedMilliseconds - lastSpeedCheck) / 1000;
            final bytesDelta = receivedBytes - lastSpeedBytes;
            state.speedBytesPerSec = bytesDelta / elapsed;
            lastSpeedCheck = stopwatch.elapsedMilliseconds;
            lastSpeedBytes = receivedBytes;
            _notifyUI(); // trigger rebuild

            // Update foreground notification with progress
            if (wakelockService != null && state.totalBytes > 0) {
              final progress = state.receivedBytes / state.totalBytes;
              final speedMb = (state.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1);
              wakelockService.updateDownloadProgress(
                modelName: model.name,
                progress: progress,
                speedText: '$speedMb MB/s',
              );
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (state.isCancelled) {
        state.isActive = false;
        activeDownloads.remove(model.filename);
        _notifyUI();
        return;
      }

      if (model.hasChecksum) {
        state.isVerifying = true;
        _notifyUI();
        final actual = await _sha256OfFile(partFile);
        state.isVerifying = false;
        if (actual != model.sha256) {
          await partFile.delete();
          throw Exception(
            'Downloaded file failed its integrity check and was discarded. '
            'Expected SHA-256 ${model.sha256}, got $actual.',
          );
        }
      }

      // Rename .part to final
      await partFile.rename(filePath);
      if (!downloadedModels.contains(model.filename)) {
        downloadedModels.add(model.filename);
      }

      state.isActive = false;
      activeDownloads.remove(model.filename);
      _notifyUI();
    } catch (e) {
      activeDownloads[model.filename]?.isActive = false;
      activeDownloads.remove(model.filename);
      _notifyUI();
      rethrow;
    } finally {
      client.close();
      state.client = null;

      // Disable wake lock if no other downloads are active
      if (activeDownloads.isEmpty) {
        try {
          await wakelockService?.disable();
        } catch (_) {}
      }
    }
  }

  /// Reject a response that is not actually a model body.
  ///
  /// Without this, a 404 page, a login redirect or an HTML interstitial was
  /// streamed to disk and renamed to .gguf, failing opaquely at load time.
  void _assertDownloadable(http.StreamedResponse response, AiModelInfo model) {
    final status = response.statusCode;
    if (status == HttpStatus.ok || status == HttpStatus.partialContent) {
      final contentType =
          response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.startsWith('text/html')) {
        throw Exception(
          'The download URL returned a web page instead of a model file. '
          'The link for ${model.name} may have moved or now require sign-in.',
        );
      }
      return;
    }

    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw Exception(
        'Access to ${model.name} was denied (HTTP $status). This model may '
        'require accepting a licence on the host before downloading.',
      );
    }
    if (status == HttpStatus.notFound) {
      throw Exception(
        'The download URL for ${model.name} no longer exists (HTTP 404).',
      );
    }
    if (status == HttpStatus.requestedRangeNotSatisfiable) {
      throw Exception(
        'Could not resume the download of ${model.name}. Delete the partial '
        'file and start again.',
      );
    }
    throw Exception('Download failed for ${model.name} (HTTP $status).');
  }

  /// Stream the file through SHA-256 so a multi-GB model is never held in RAM.
  Future<String> _sha256OfFile(File file) async {
    final digest = await file.openRead().transform(sha256).first;
    return digest.toString();
  }

  /// Cancel an active download.
  void cancelDownload(String filename) {
    final state = activeDownloads[filename];
    if (state != null) {
      state.isCancelled = true;
      state.isActive = false;
      // Close only this transfer's client — closing a shared one used to kill
      // every other download in flight.
      state.client?.close();
      state.client = null;
    }
    activeDownloads.remove(filename);
    _notifyUI();
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String filename) async {
    final file = File(p.join(_modelsDir, filename));
    if (await file.exists()) {
      await file.delete();
    }
    downloadedModels.remove(filename);
  }

  /// Move a model file from cache to the models directory (instant on most file systems).
  Future<void> moveModel(String sourcePath, String filename) async {
    final destPath = p.join(_modelsDir, filename);
    if (sourcePath == destPath) return;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    // Try to move the file instantly (rename)
    try {
      await sourceFile.rename(destPath);
    } catch (e) {
      // Fallback to copy if rename fails (e.g. across different partitions)
      await sourceFile.copy(destPath);
      await sourceFile.delete();
    }

    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Import a model directly from a stream (useful to bypass FilePicker caching on Android/iOS).
  Future<void> importModelFromStream({
    required String filename,
    required Stream<List<int>> stream,
    required int totalBytes,
    Function(double)? onProgress,
    bool Function()? checkCancelled,
  }) async {
    final destPath = p.join(_modelsDir, filename);
    final destFile = File(destPath);
    
    final sink = destFile.openWrite();
    int copiedBytes = 0;
    bool wasCancelled = false;

    try {
      final mappedStream = stream.map((chunk) {
        if (checkCancelled?.call() == true) {
          throw const FormatException('CANCELLED');
        }
        copiedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(copiedBytes / totalBytes);
        }
        return chunk;
      });
      await sink.addStream(mappedStream);
    } on FormatException catch (e) {
      if (e.message == 'CANCELLED') {
        wasCancelled = true;
      } else {
        rethrow;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (wasCancelled) {
      if (await destFile.exists()) {
        await destFile.delete();
      }
      return;
    }

    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Import a model file from external path with progress tracking.
  Future<void> importModel(String sourcePath, {Function(double)? onProgress, bool Function()? checkCancelled}) async {
    final filename = p.basename(sourcePath);
    final destPath = p.join(_modelsDir, filename);

    if (sourcePath != destPath) {
      final sourceFile = File(sourcePath);
      final destFile = File(destPath);
      
      final totalBytes = await sourceFile.length();
      if (totalBytes == 0) return;

      final sourceStream = sourceFile.openRead();
      final sink = destFile.openWrite();

      int copiedBytes = 0;
      bool wasCancelled = false;

      try {
        final mappedStream = sourceStream.map((chunk) {
          if (checkCancelled?.call() == true) {
            throw const FormatException('CANCELLED');
          }
          copiedBytes += chunk.length;
          onProgress?.call(copiedBytes / totalBytes);
          return chunk;
        });
        await sink.addStream(mappedStream);
      } on FormatException catch (e) {
        if (e.message == 'CANCELLED') {
          wasCancelled = true;
        } else {
          rethrow;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (wasCancelled) {
        if (await destFile.exists()) {
          await destFile.delete();
        }
        return;
      }
    }

    if (!downloadedModels.contains(filename)) {
      downloadedModels.add(filename);
    }
  }

  /// Add custom model to catalog and persist it.
  void addCustomModel(AiModelInfo model) {
    catalog.add(model);
    _persistCustomModels();
  }

  /// Remove a custom model from catalog and persistence.
  void removeCustomModel(String id) {
    catalog.removeWhere((m) => m.id == id);
    _persistCustomModels();
  }

  /// Save all custom models to Hive.
  void _persistCustomModels() {
    final box = Hive.box('models_meta');
    final customList = catalog
        .where((m) => m.isCustom)
        .map((m) => m.toJson())
        .toList();
    box.put('custom_models', customList);
  }

  @override
  void onClose() {
    for (final state in activeDownloads.values) {
      state.isCancelled = true;
      state.client?.close();
      state.client = null;
    }
    super.onClose();
  }
}
