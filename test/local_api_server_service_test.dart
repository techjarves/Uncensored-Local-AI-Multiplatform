import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:portable_ai_flutter/models/chat_model.dart';
import 'package:portable_ai_flutter/models/message_model.dart';
import 'package:portable_ai_flutter/services/chat_storage_service.dart';
import 'package:portable_ai_flutter/services/llm_service.dart';
import 'package:portable_ai_flutter/services/local_api_server_service.dart';

void main() {
  late Directory tempDir;
  late LocalApiServerService apiServer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('portable-ai-api-test-');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChatModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MessageRoleAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MessageModelAdapter());
    }

    await Hive.openBox<ChatModel>('chats');
    await Hive.openBox('settings');

    final storage = await ChatStorageService().init();
    Get.put<LlmService>(LlmService());
    Get.put<ChatStorageService>(storage);
    apiServer = Get.put<LocalApiServerService>(LocalApiServerService());
  });

  tearDown(() async {
    await apiServer.stop();
    Get.reset();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('init starts the localhost server by default', () async {
    final port = await _freePort();
    Get.find<ChatStorageService>().localApiServerPort = port;
    Get.find<ChatStorageService>().localApiServerEnabled = true;

    await apiServer.init();

    expect(apiServer.isRunning.value, isTrue);
    final health = await _getJson('http://127.0.0.1:$port/healthz');
    expect(health['status'], 'ok');
  });

  test(
    'starts, reports health, and returns an OpenAI model list shape',
    () async {
      final port = await _freePort();
      await apiServer.start(requestedPort: port);

      final health = await _getJson('http://127.0.0.1:$port/healthz');
      expect(health['status'], 'ok');
      expect(health['ready'], isFalse);
      expect(health['base_url'], 'http://127.0.0.1:$port/v1');

      final models = await _getJson('http://127.0.0.1:$port/v1/models');
      expect(models['object'], 'list');
      expect(models['data'], isA<List>());
    },
  );

  test(
    'chat completions return OpenAI-style error when no model is loaded',
    () async {
      final port = await _freePort();
      await apiServer.start(requestedPort: port);

      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'model': 'local',
            'messages': [
              {'role': 'user', 'content': 'Hello'},
            ],
          }),
        );

        final response = await request.close();
        final body =
            jsonDecode(await utf8.decoder.bind(response).join())
                as Map<String, dynamic>;

        expect(response.statusCode, HttpStatus.serviceUnavailable);
        expect(body['error'], isA<Map>());
        expect((body['error'] as Map)['code'], 'model_not_loaded');
      } finally {
        client.close(force: true);
      }
    },
  );
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<Map<String, dynamic>> _getJson(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}
