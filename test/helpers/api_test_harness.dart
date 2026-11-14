import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:portable_ai_flutter/models/chat_model.dart';
import 'package:portable_ai_flutter/models/message_model.dart';
import 'package:portable_ai_flutter/services/chat_storage_service.dart';
import 'package:portable_ai_flutter/services/llm_service.dart';
import 'package:portable_ai_flutter/services/local_api_server_service.dart';

/// Shared setup for local API server tests.
///
/// Gives each test an isolated Hive directory, a wired GetX graph, and a
/// small HTTP client so the tests read as request/response pairs rather than
/// dart:io boilerplate.
class ApiTestHarness {
  late Directory tempDir;
  late ChatStorageService storage;
  late LocalApiServerService api;

  Future<void> setUp() async {
    tempDir = await Directory.systemTemp.createTemp('ula-api-test-');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ChatModelAdapter());
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MessageRoleAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MessageModelAdapter());
    }

    await Hive.openBox<ChatModel>('chats');
    await Hive.openBox('settings');

    storage = await ChatStorageService().init();
    Get.put<LlmService>(LlmService());
    Get.put<ChatStorageService>(storage);
    api = Get.put<LocalApiServerService>(LocalApiServerService());
  }

  Future<void> tearDown() async {
    await api.stop();
    Get.reset();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  /// The token the server currently expects.
  String get token => api.apiToken.value;

  Map<String, String> get authHeaders => {
    'authorization': 'Bearer ${api.apiToken.value}',
  };

  /// Bind on an ephemeral port and return it.
  Future<int> startOnFreePort() async {
    final port = await freePort();
    await api.start(requestedPort: port);
    return port;
  }

  /// An unauthenticated request. Most tests want [send] instead.
  Future<ApiResponse> sendRaw(
    String method,
    String url, {
    String? body,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      headers?.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final collected = <String, String>{};
      response.headers.forEach((k, v) => collected[k] = v.join(','));
      return ApiResponse(response.statusCode, text, collected);
    } finally {
      client.close(force: true);
    }
  }

  /// An authenticated request.
  Future<ApiResponse> send(
    String method,
    String url, {
    String? body,
    Map<String, String>? headers,
  }) {
    return sendRaw(
      method,
      url,
      body: body,
      headers: {...authHeaders, ...?headers},
    );
  }
}

class ApiResponse {
  final int status;
  final String body;
  final Map<String, String> headers;

  ApiResponse(this.status, this.body, this.headers);

  Map<String, dynamic> get json =>
      jsonDecode(body) as Map<String, dynamic>;

  /// The OpenAI `error` object, or null when the body is not an error.
  Map<String, dynamic>? get error {
    final decoded = json['error'];
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  String? get errorCode => error?['code'] as String?;
}

/// Bind and release a socket to discover a port nothing else is using.
Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// True when something is serving /healthz on [port].
Future<bool> isServing(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final response =
        await (await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/healthz'),
        )).close();
    await response.drain<void>();
    return response.statusCode == HttpStatus.ok;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
