import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../services/llm_service.dart';
import '../services/model_manager.dart';
import '../services/chat_storage_service.dart';
import '../services/local_api_server_service.dart';
import '../services/wakelock_service.dart';
import '../services/log_service.dart';
import '../services/background_optimizer_service.dart';
import '../routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Initializing...';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  /// setState after an await is only safe while the widget is still mounted.
  void _setStatus(String status) {
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _initApp() async {
    if (mounted) setState(() => _error = '');
    try {
      // Initialize logging first
      final log = Get.find<LogService>()..init();

      _setStatus('Setting up storage...');
      log.info('Initializing storage...', source: 'Splash');
      await Get.find<ChatStorageService>().init();

      _setStatus('Loading model catalog...');
      log.info('Loading model catalog...', source: 'Splash');
      await Get.find<ModelManager>().init();

      _setStatus('Preparing AI engine...');
      log.info('Preparing AI engine...', source: 'Splash');
      await Get.find<LlmService>().init();

      // Background services must come up before the API server, which
      // acquires a wake lock as soon as it binds. Starting the foreground
      // service before FlutterForegroundTask.init() has run silently fails
      // on Android.
      _setStatus('Setting up background services...');
      log.info('Setting up background services...', source: 'Splash');
      await Get.find<WakelockService>().init();

      _setStatus('Preparing local API...');
      log.info('Preparing local API...', source: 'Splash');
      await Get.find<LocalApiServerService>().init();

      _setStatus('Ready!');
      log.info('All services initialized successfully', source: 'Splash');
      await Future.delayed(const Duration(milliseconds: 500));

      // Prompt for battery optimization on Android (first launch only)
      if (mounted) {
        await BackgroundOptimizerService.checkAndPrompt(context);
      }

      Get.offAllNamed(AppRoutes.home);
    } catch (e) {
      // Startup used to stop here with a bare error string and no way out,
      // which left anyone with a corrupt box permanently stuck on the splash.
      if (mounted) {
        setState(() {
          _status = 'Startup failed';
          _error = e.toString();
        });
      }
      try {
        Get.find<LogService>().error('Init failed: $e', source: 'Splash');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 24),
            Text(
              'Uncensored Local AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: context.text,
                letterSpacing: -0.5,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 600.ms),
            const SizedBox(height: 8),
            Text(
              'Run uncensored LLMs natively on any device 🔓',
              style: TextStyle(fontSize: 13, color: context.textM),
            ).animate().fadeIn(delay: 400.ms, duration: 600.ms),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 16),
            Text(
              _status,
              style: TextStyle(fontSize: 12, color: context.textD),
            ).animate().fadeIn(delay: 600.ms),
            if (_error.isNotEmpty) _buildErrorActions(context),
          ],
        ),
      ),
    );
  }

  /// Shown when startup fails, so the user can retry or push past a service
  /// that will not come up rather than being stuck on the splash forever.
  Widget _buildErrorActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: context.textM),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _status = 'Retrying...';
                      _error = '';
                    });
                    _initApp();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Get.offAllNamed(AppRoutes.home),
                  child: Text(
                    'Continue anyway',
                    style: TextStyle(color: context.textM),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
