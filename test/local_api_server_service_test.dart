import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/api_test_harness.dart';

void main() {
  final harness = ApiTestHarness();

  setUp(harness.setUp);
  tearDown(harness.tearDown);

  test('init starts the localhost server by default', () async {
    final port = await freePort();
    harness.storage.localApiServerPort = port;
    harness.storage.localApiServerEnabled = true;

    await harness.api.init();

    expect(harness.api.isRunning.value, isTrue);
    final health = await harness.sendRaw(
      'GET',
      'http://127.0.0.1:$port/healthz',
    );
    expect(health.json['status'], 'ok');
  });

  test(
    'starts, reports health, and returns an OpenAI model list shape',
    () async {
      final port = await harness.startOnFreePort();

      final health = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/healthz',
      );
      expect(health.json['status'], 'ok');
      expect(health.json['ready'], isFalse);
      expect(health.json['base_url'], 'http://127.0.0.1:$port/v1');
      expect(health.json['auth_required'], isTrue);

      final models = await harness.send(
        'GET',
        'http://127.0.0.1:$port/v1/models',
      );
      expect(models.json['object'], 'list');
      expect(models.json['data'], isA<List>());
    },
  );

  test(
    'chat completions return OpenAI-style error when no model is loaded',
    () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'POST',
        'http://127.0.0.1:$port/v1/chat/completions',
        body: jsonEncode({
          'model': 'local',
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
        }),
      );

      expect(response.status, HttpStatus.serviceUnavailable);
      expect(response.error, isA<Map>());
      expect(response.errorCode, 'model_not_loaded');
    },
  );
}
