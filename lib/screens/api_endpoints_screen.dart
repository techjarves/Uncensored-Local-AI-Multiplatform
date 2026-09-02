import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../services/local_api_server_service.dart';

class ApiEndpointsScreen extends StatefulWidget {
  const ApiEndpointsScreen({super.key});

  @override
  State<ApiEndpointsScreen> createState() => _ApiEndpointsScreenState();
}

class _ApiEndpointsScreenState extends State<ApiEndpointsScreen> {
  final apiServer = Get.find<LocalApiServerService>();
  
  bool _testing = false;
  String _testResult = '';

  Future<void> _testEndpoint(String path) async {
    if (!apiServer.isRunning.value) {
      Get.snackbar('Error', 'API server is not running', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() {
      _testing = true;
      _testResult = 'Fetching...';
    });

    try {
      // Always use localhost for internal testing, even if bound to 0.0.0.0
      final url = 'http://127.0.0.1:${apiServer.port.value}$path';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonDecode(response.body));
        setState(() {
          _testResult = 'Status: 200 OK\n\n$jsonStr';
        });
      } else {
        setState(() {
          _testResult = 'Error: ${response.statusCode}\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Request failed:\n$e';
      });
    } finally {
      setState(() {
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bgPanel,
        title: const Text('Sample Endpoints', style: TextStyle(fontSize: 16)),
        elevation: 0,
        centerTitle: true,
      ),
      body: Obx(() {
        final baseUrl = apiServer.baseUrl;
        final running = apiServer.isRunning.value;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: running ? AppColors.green.withValues(alpha: 0.1) : AppColors.red.withValues(alpha: 0.1),
                border: Border.all(
                  color: running ? AppColors.green.withValues(alpha: 0.3) : AppColors.red.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    running ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: running ? AppColors.green : AppColors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Server Status: ${running ? 'Running' : 'Stopped'}',
                          style: TextStyle(
                            color: running ? AppColors.green : AppColors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (running)
                          Text(
                            'Base URL: $baseUrl',
                            style: TextStyle(color: context.textD, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'How to Access',
              style: TextStyle(color: context.text, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The app runs a local HTTP server compatible with the OpenAI API format. You can point any app, script, or tool (like LangChain or AutoGPT) to this Base URL.',
              style: TextStyle(color: context.textM, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),

            // Endpoints
            _buildEndpointCard(
              context: context,
              method: 'GET',
              path: '/v1/models',
              description: 'List available models (currently loaded model).',
              onTest: () => _testEndpoint('/v1/models'),
            ),
            const SizedBox(height: 16),
            
            _buildEndpointCard(
              context: context,
              method: 'POST',
              path: '/v1/chat/completions',
              description: 'Generate a chat completion. Accepts messages array in standard format.',
              onTest: null, // POST is harder to just "test" with a simple button without a payload builder
            ),

            const SizedBox(height: 32),

            // Test Output Area
            if (_testResult.isNotEmpty) ...[
              Text(
                'Test Output',
                style: TextStyle(color: context.text, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.isDark ? Colors.black26 : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.border),
                ),
                child: SelectableText(
                  _testResult,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AppColors.accentHi,
                  ),
                ),
              ),
            ]
          ],
        );
      }),
    );
  }

  Widget _buildEndpointCard({
    required BuildContext context,
    required String method,
    required String path,
    required String description,
    VoidCallback? onTest,
  }) {
    final isGet = method == 'GET';
    final methodColor = isGet ? AppColors.green : AppColors.orange;

    return Container(
      decoration: BoxDecoration(
        color: context.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    method,
                    style: TextStyle(
                      color: methodColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    path,
                    style: TextStyle(
                      color: context.text,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTest != null)
                  ElevatedButton(
                    onPressed: _testing ? null : onTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(60, 30),
                    ),
                    child: const Text('Test', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              description,
              style: TextStyle(color: context.textM, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
