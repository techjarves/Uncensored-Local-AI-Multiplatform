import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import 'wakelock_service.dart';
import 'chat_storage_service.dart';
import 'log_service.dart';

/// Wraps llamadart's LlamaEngine for model loading, generation, and lifecycle.
class LlmService extends GetxService {
  LlamaEngine? _engine;
  LlamaBackend? _backend;

  final isLoaded = false.obs;
  final isGenerating = false.obs;
  final loadedModelPath = ''.obs;
  final tokensPerSecond = 0.0.obs;
  final lastGenerationTokens = 0.obs;
  final lastGenerationSpeed = 0.0.obs;

  /// Context window of the loaded model, in tokens. Set at load time.
  final contextTokens = 2048.obs;

  /// How many messages the last request dropped to fit the context window.
  final lastTrimmedMessages = 0.obs;

  // ── Loading progress tracking ──────────────────────────────
  final isLoadingModel = false.obs;
  final loadingProgress = 0.0.obs; // 0.0 to 1.0
  final loadingStatusMsg = ''.obs;
  bool _loadingCancelled = false;

  String get loadedModelFilename {
    final path = loadedModelPath.value;
    if (path.isEmpty) return '';
    return p.basename(path);
  }

  String get publicModelId {
    final filename = loadedModelFilename;
    if (filename.isEmpty) return 'local';
    final stem = filename.toLowerCase().endsWith('.gguf')
        ? filename.substring(0, filename.length - 5)
        : p.basenameWithoutExtension(filename);
    return stem
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Initialize the service.
  Future<LlmService> init() async {
    // Backend is created fresh per loadModel() call — no init needed here
    return this;
  }

  /// Cancel an in-progress model load.
  void cancelLoading() {
    _loadingCancelled = true;
  }

  /// Load a GGUF model from [path] with progress tracking.
  Future<void> loadModel(String path) async {
    LogService? log;
    try { log = Get.find<LogService>(); } catch (_) {}

    // Verify file exists first
    final file = File(path);
    if (!await file.exists()) {
      log?.error('Model file not found: $path', source: 'LLM');
      throw Exception('Model file not found: $path');
    }

    final filename = p.basename(path);
    log?.info('Loading model: $filename', source: 'LLM');

    _loadingCancelled = false;
    isLoadingModel.value = true;
    loadingProgress.value = 0.0;
    loadingStatusMsg.value = 'Preparing...';

    // Enable wake lock during model loading (heavy memory operation)
    WakelockService? wakelockService;
    try {
      wakelockService = Get.find<WakelockService>();
    } catch (_) {}

    // Unload previous if any — MUST fully tear down engine + backend
    if (_engine != null || isLoaded.value) {
      loadingStatusMsg.value = 'Unloading previous model...';
      loadingProgress.value = 0.05;
      await _fullTeardown();
      // Give native side time to release resources
      await Future.delayed(const Duration(milliseconds: 500));
      if (_loadingCancelled) {
        _resetLoadingState();
        return;
      }
    }

    // Fresh backend + engine for every load — prevents stale native state
    // Wrapped in try-catch to handle SELinux crashes on Android where
    // ggml_backend_load_all() attempts to scan '/' which is denied.
    try {
      _backend = LlamaBackend();
      _engine = LlamaEngine(_backend!);
    } catch (e) {
      _backend = null;
      _engine = null;
      _resetLoadingState();
      log?.error('Engine init failed: $e', source: 'LLM');
      throw Exception(
        'Failed to initialize AI engine. '
        'This may be a device compatibility issue. '
        'Error: $e',
      );
    }

    try {
      loadingStatusMsg.value = 'Loading into memory...';
      loadingProgress.value = 0.1;

      // Get file size for display
      final fileSize = await file.length();
      final sizeGb = (fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1);
      loadingStatusMsg.value = 'Loading $sizeGb GB into memory...';

      // Start a timer to animate progress while loading
      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 300), (
        timer,
      ) {
        if (_loadingCancelled) {
          timer.cancel();
          return;
        }
        // Gradually increase progress (asymptotic approach to 0.95)
        final current = loadingProgress.value;
        if (current < 0.95) {
          loadingProgress.value = current + (0.95 - current) * 0.04;
        }
      });

      if (_loadingCancelled) {
        progressTimer.cancel();
        await _fullTeardown();
        _resetLoadingState();
        return;
      }

      // Use smaller context on Android to prevent OOM kills.
      // Desktop can handle 2048, but Android devices with limited RAM
      // need 1024 to avoid the Low Memory Killer (LMK).
      final contextSize = Platform.isAndroid ? 1024 : 2048;
      contextTokens.value = contextSize;

      // Map the string backend to GpuBackend enum
      final storage = Get.find<ChatStorageService>();
      GpuBackend parsedBackend;
      switch (storage.backendType) {
        case 'vulkan':
          parsedBackend = GpuBackend.vulkan;
          break;
        case 'opencl':
          parsedBackend = GpuBackend.opencl;
          break;
        default:
          parsedBackend = GpuBackend.cpu;
      }

      // Read gpu layers
      final userGpuLayers = storage.gpuLayers;

      // Optimize threads: 4 for both generation and batch processing to keep memory stable.
      final params = ModelParams(
        contextSize: contextSize,
        gpuLayers: userGpuLayers, 
        preferredBackend: parsedBackend,
        numberOfThreads: Platform.numberOfProcessors > 4 ? 4 : 0, 
        numberOfThreadsBatch: Platform.numberOfProcessors > 4 ? 4 : 0,
      );

      log?.info('Backend=$parsedBackend, GPU layers=$userGpuLayers, ctx=$contextSize, threads=${Platform.numberOfProcessors > 4 ? 4 : 0}', source: 'LLM');

      await _engine!.loadModel(path, modelParams: params);
      progressTimer.cancel();

      if (_loadingCancelled) {
        // User cancelled while loading — full cleanup
        await _fullTeardown();
        _resetLoadingState();
        return;
      }

      loadingProgress.value = 1.0;
      loadingStatusMsg.value = 'Ready!';
      isLoaded.value = true;
      loadedModelPath.value = path;
      log?.info('Model loaded successfully: $filename', source: 'LLM');

      // Enable wake lock for inference on mobile (keeps app from being killed)
      final modelName = p.basenameWithoutExtension(path);
      await wakelockService?.enableForInference(modelName: modelName);

      // Brief delay to show 100%
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      isLoaded.value = false;
      loadedModelPath.value = '';
      await _fullTeardown();
      log?.error('Model load failed: $e', source: 'LLM');

      // Provide a clearer error message for common Android failures
      if (Platform.isAndroid) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('memory') || errStr.contains('alloc')) {
          throw Exception(
            'Not enough RAM to load this model. '
            'Try a smaller model (e.g. Gemma 2 2B at 1.6 GB).',
          );
        }
      }
      rethrow;
    } finally {
      _resetLoadingState();
    }
  }

  void _resetLoadingState() {
    isLoadingModel.value = false;
    loadingProgress.value = 0.0;
    loadingStatusMsg.value = '';
    _loadingCancelled = false;
  }

  /// Rough token estimate used for context budgeting.
  ///
  /// Counting exactly would mean a native call per message on every turn;
  /// 3.6 chars/token is conservative for English across the GGUF tokenizers
  /// this app ships, and the reserve below absorbs the error.
  static const _charsPerToken = 3.6;

  static int _estimateTokens(String text) =>
      (text.length / _charsPerToken).ceil() + 4;

  /// Drop the oldest turns until the conversation fits the context window.
  ///
  /// System messages are always kept. [reserveTokens] leaves room for the
  /// model's own reply, without which llama.cpp truncates the prompt itself
  /// and the model silently forgets the start of the conversation.
  List<LlamaChatMessage> trimToContext(
    List<LlamaChatMessage> messages, {
    int reserveTokens = 512,
  }) {
    final budget = contextTokens.value - reserveTokens;
    if (budget <= 0) {
      lastTrimmedMessages.value = 0;
      return messages;
    }

    final system = messages
        .where((m) => m.role == LlamaChatRole.system)
        .toList(growable: false);
    final turns = messages
        .where((m) => m.role != LlamaChatRole.system)
        .toList();

    var total = messages.fold<int>(
      0,
      (sum, m) => sum + _estimateTokens(m.content),
    );

    var dropped = 0;
    // Always keep the most recent turn, even if it alone exceeds the budget —
    // llama.cpp will truncate it, but sending nothing is worse.
    while (total > budget && turns.length > 1) {
      total -= _estimateTokens(turns.removeAt(0).content);
      dropped++;
    }

    lastTrimmedMessages.value = dropped;
    if (dropped == 0) return messages;
    return [...system, ...turns];
  }

  static LlamaChatRole _roleFromString(String? role) {
    switch (role) {
      case 'system':
      case 'developer':
        return LlamaChatRole.system;
      case 'assistant':
        return LlamaChatRole.assistant;
      case 'tool':
        return LlamaChatRole.tool;
      default:
        return LlamaChatRole.user;
    }
  }

  /// Generate a streaming response for the in-app chat.
  ///
  /// Delegates to [generateChatCompletion] so the model's own chat template is
  /// applied. Hand-building a prompt here previously emitted a fixed
  /// pseudo-ChatML format to every model regardless of what it expected, which
  /// degraded output on Gemma, Llama 3 and Mistral alike.
  Stream<String> generate({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 0.7,
  }) {
    final chatMessages = <LlamaChatMessage>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      chatMessages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: systemPrompt,
        ),
      );
    }

    for (final message in messages) {
      chatMessages.add(
        LlamaChatMessage.fromText(
          role: _roleFromString(message['role']),
          text: message['content'] ?? '',
        ),
      );
    }

    return generateChatCompletion(
      messages: trimToContext(chatMessages),
      params: GenerationParams(
        temp: temperature,
        penalty: 1.0,
        topP: 0.95,
        minP: 0.05,
      ),
    );
  }

  /// Generate a chat completion using llamadart's chat-template API.
  Stream<String> generateChatCompletion({
    required List<LlamaChatMessage> messages,
    GenerationParams params = const GenerationParams(),
  }) async* {
    if (_engine == null || !isLoaded.value) {
      throw StateError('No model loaded. Call loadModel() first.');
    }
    if (isGenerating.value) {
      throw StateError('Another generation is already in progress.');
    }

    isGenerating.value = true;
    tokensPerSecond.value = 0.0;
    final stopwatch = Stopwatch()..start();
    int tokenCount = 0;

    try {
      await for (final chunk in _engine!.create(
        messages,
        params: params,
        toolChoice: ToolChoice.none,
      )) {
        final choice = chunk.choices.isNotEmpty ? chunk.choices.first : null;
        final content = choice?.delta.content;
        if (content == null || content.isEmpty) continue;

        tokenCount++;
        if (stopwatch.elapsedMilliseconds > 0) {
          tokensPerSecond.value =
              tokenCount / (stopwatch.elapsedMilliseconds / 1000);
        }
        yield content;
      }
    } finally {
      stopwatch.stop();
      lastGenerationTokens.value = tokenCount;
      lastGenerationSpeed.value = tokensPerSecond.value;
      isGenerating.value = false;
    }
  }

  Future<int> countTokens(String text) async {
    if (_engine == null || !isLoaded.value) return 0;
    try {
      return await _engine!.getTokenCount(text);
    } catch (_) {
      return 0;
    }
  }

  /// Stop ongoing generation.
  Future<void> stopGeneration() async {
    _engine?.cancelGeneration();
    isGenerating.value = false;
  }

  /// Full native teardown — dispose engine AND backend to prevent stale state.
  Future<void> _fullTeardown() async {
    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (_) {
        // Engine may already be in broken state — ignore
      }
      _engine = null;
    }
    // Also destroy the backend — it can't be reused after engine disposal
    _backend = null;
    isLoaded.value = false;
    loadedModelPath.value = '';
    tokensPerSecond.value = 0.0;
  }

  /// Unload the current model and free memory.
  Future<void> unloadModel() async {
    await _fullTeardown();

    // Disable wake lock when model is unloaded
    try {
      final wakelockService = Get.find<WakelockService>();
      await wakelockService.disable();
    } catch (_) {}
  }

  @override
  void onClose() {
    unloadModel();
    super.onClose();
  }
}
