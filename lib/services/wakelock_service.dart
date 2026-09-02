import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages wake lock (screen stays on) and Android foreground service
/// to prevent the OS from killing downloads and inference.
class WakelockService extends GetxService {
  /// Reason a caller holds the wake lock.
  static const holderDownload = 'download';
  static const holderModel = 'model';
  static const holderApiServer = 'api';

  final isWakeLockActive = false.obs;

  /// Everything currently needing the device awake.
  ///
  /// Downloads, a loaded model and the API server each acquire independently.
  /// Without this, whichever finished first called disable() and killed the
  /// foreground service the others were still relying on.
  final _holders = <String>{};

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// True once init() has run. startService() before FlutterForegroundTask
  /// has been configured fails, so callers must not jump the gun.
  bool _initialized = false;

  Set<String> get activeHolders => Set.unmodifiable(_holders);

  Future<WakelockService> init() async {
    if (_isMobile) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'portable_ai_foreground',
          channelName: 'Uncensored Local AI',
          channelDescription: 'Keeps downloads and AI inference running',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      
      // Request notification permission for Android 13+
      await FlutterForegroundTask.requestNotificationPermission();
    }
    _initialized = true;
    return this;
  }

  /// Acquire the wake lock on behalf of [holder].
  ///
  /// Safe to call repeatedly; the lock is only released once every holder has
  /// called [release].
  Future<void> acquire(
    String holder, {
    required String title,
    required String text,
  }) async {
    _holders.add(holder);
    if (!_isMobile || !_initialized) return;

    try {
      await WakelockPlus.enable();
      isWakeLockActive.value = true;

      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
        serviceId: 100,
      );
    } catch (e) {
      debugPrint('WakelockService.acquire($holder) error: $e');
    }
  }

  /// Release [holder]'s claim. Stops the service only when nothing else holds it.
  Future<void> release(String holder) async {
    _holders.remove(holder);
    if (_holders.isNotEmpty) return;
    await _stop();
  }

  /// Enable wake lock + foreground service for model download.
  Future<void> enableForDownload({String modelName = 'model'}) {
    return acquire(
      holderDownload,
      title: 'Downloading $modelName',
      text: 'Download in progress — keep the app open',
    );
  }

  /// Release the download claim.
  Future<void> releaseDownload() => release(holderDownload);

  /// Acquire on behalf of the local API server.
  Future<void> enableForApiServer() {
    return acquire(
      holderApiServer,
      title: 'Local API Server Running',
      text: 'Serving requests on localhost',
    );
  }

  /// Release the API server claim.
  Future<void> releaseApiServer() => release(holderApiServer);

  /// Release the loaded-model claim.
  Future<void> releaseModel() => release(holderModel);

  /// Update the foreground notification with download progress.
  Future<void> updateDownloadProgress({
    required String modelName,
    required double progress,
    String? speedText,
  }) async {
    if (!_isMobile) return;

    try {
      final pct = (progress * 100).toInt();
      final speed = speedText != null ? ' • $speedText' : '';
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Downloading $modelName — $pct%',
        notificationText: 'Download in progress$speed',
      );
    } catch (_) {}
  }

  /// Enable wake lock + foreground service for a loaded model.
  Future<void> enableForInference({String modelName = 'AI model'}) {
    return acquire(
      holderModel,
      title: 'AI Model Active',
      text: '$modelName is loaded and ready',
    );
  }

  /// Drop every claim and stop the foreground service.
  ///
  /// Only for app teardown — scoped callers should use [release] so they do
  /// not tear down a service another subsystem still needs.
  Future<void> disable() async {
    _holders.clear();
    await _stop();
  }

  Future<void> _stop() async {
    if (!_isMobile) return;

    try {
      await WakelockPlus.disable();
      isWakeLockActive.value = false;
    } catch (_) {}

    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  @override
  void onClose() {
    disable();
    super.onClose();
  }
}
