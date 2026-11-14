import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/api_test_harness.dart';

/// Regression tests for defects found auditing the local API server.
///
/// Each group names the behaviour that used to be wrong, so a future
/// refactor that reintroduces it fails here with an obvious message.
void main() {
  final harness = ApiTestHarness();

  setUp(harness.setUp);
  tearDown(harness.tearDown);

  group('reconfiguration actually rebinds the listener', () {
    test('setPort moves the server to the new port', () async {
      final oldPort = await harness.startOnFreePort();
      final newPort = await freePort();

      final ok = await harness.api.setPort(newPort);

      expect(ok, isTrue);
      expect(harness.api.port.value, newPort);
      expect(
        await isServing(newPort),
        isTrue,
        reason: 'the new port must accept connections',
      );
      expect(
        await isServing(oldPort),
        isFalse,
        reason: 'the old listener must be closed, not orphaned',
      );
    });

    test('health reports the port it is actually listening on', () async {
      await harness.startOnFreePort();
      final newPort = await freePort();
      await harness.api.setPort(newPort);

      final health = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$newPort/healthz',
      );

      expect(health.json['port'], newPort);
      expect(health.json['base_url'], 'http://127.0.0.1:$newPort/v1');
    });

    test('setAllInterfaces rebinds from loopback to 0.0.0.0', () async {
      final port = await harness.startOnFreePort();

      final ok = await harness.api.setAllInterfaces(true);

      expect(ok, isTrue);
      expect(harness.api.allInterfaces.value, isTrue);
      expect(harness.api.host, '0.0.0.0');
      expect(await isServing(port), isTrue);

      // Rebinding back to loopback must also take effect.
      expect(await harness.api.setAllInterfaces(false), isTrue);
      expect(harness.api.allInterfaces.value, isFalse);
      expect(await isServing(port), isTrue);
    });

    test('restarting on the same endpoint is a cheap no-op', () async {
      final port = await harness.startOnFreePort();
      await harness.api.start(requestedPort: port);

      expect(harness.api.isRunning.value, isTrue);
      expect(await isServing(port), isTrue);
    });

    test('an out-of-range port is refused, not silently substituted', () async {
      final port = await harness.startOnFreePort();

      final ok = await harness.api.setPort(80);

      expect(ok, isFalse, reason: 'caller must learn the change failed');
      expect(harness.api.errorMessage.value, contains('1024'));
      expect(
        harness.api.port.value,
        port,
        reason: 'the server keeps serving the port it is actually bound to',
      );
      expect(await isServing(port), isTrue);
    });

    test('a bind conflict leaves the service stopped and explains why',
        () async {
      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        await harness.api.start(requestedPort: blocker.port);

        expect(harness.api.isRunning.value, isFalse);
        expect(harness.api.errorMessage.value, isNotEmpty);
      } finally {
        await blocker.close();
      }
    });
  });

  group('authentication', () {
    test('a request with no key is rejected', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/v1/models',
      );

      expect(response.status, HttpStatus.unauthorized);
      expect(response.errorCode, 'invalid_api_key');
    });

    test('a wrong key is rejected', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/v1/models',
        headers: {'authorization': 'Bearer not-the-real-key'},
      );

      expect(response.status, HttpStatus.unauthorized);
    });

    test('the correct key is accepted', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'GET',
        'http://127.0.0.1:$port/v1/models',
      );

      expect(response.status, HttpStatus.ok);
    });

    test('the api_key query parameter is accepted for clients that need it',
        () async {
      final port = await harness.startOnFreePort();

      final response = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/v1/models?api_key=${harness.token}',
      );

      expect(response.status, HttpStatus.ok);
    });

    test('healthz stays open and never leaks the token', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/healthz',
      );

      expect(response.status, HttpStatus.ok);
      expect(response.body, isNot(contains(harness.token)));
    });

    test('regenerating the token invalidates the previous one', () async {
      final port = await harness.startOnFreePort();
      final oldToken = harness.token;

      harness.api.regenerateToken();

      expect(harness.api.apiToken.value, isNot(oldToken));

      final stale = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/v1/models',
        headers: {'authorization': 'Bearer $oldToken'},
      );
      expect(stale.status, HttpStatus.unauthorized);

      final fresh = await harness.send(
        'GET',
        'http://127.0.0.1:$port/v1/models',
      );
      expect(fresh.status, HttpStatus.ok);
    });

    test('auth cannot be disabled while exposed on all interfaces', () async {
      await harness.startOnFreePort();
      await harness.api.setAllInterfaces(true);

      expect(harness.api.authLocked, isTrue);
      expect(harness.api.setRequireAuth(false), isFalse);
      expect(harness.api.requireAuth.value, isTrue);
    });

    test('auth can be disabled deliberately on loopback', () async {
      final port = await harness.startOnFreePort();

      expect(harness.api.setRequireAuth(false), isTrue);

      final response = await harness.sendRaw(
        'GET',
        'http://127.0.0.1:$port/v1/models',
      );
      expect(response.status, HttpStatus.ok);
    });
  });

  group('request validation runs before model readiness', () {
    test('malformed JSON is a 400, not a masked 503', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'POST',
        'http://127.0.0.1:$port/v1/chat/completions',
        body: '{not json',
      );

      expect(response.status, HttpStatus.badRequest);
      expect(response.errorCode, isNot('model_not_loaded'));
    });

    test('an empty messages array reports the offending param', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'POST',
        'http://127.0.0.1:$port/v1/chat/completions',
        body: jsonEncode({'model': 'local', 'messages': []}),
      );

      expect(response.status, HttpStatus.badRequest);
      expect(response.error?['param'], 'messages');
    });

    test('an unsupported role is reported precisely', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'POST',
        'http://127.0.0.1:$port/v1/chat/completions',
        body: jsonEncode({
          'messages': [
            {'role': 'wizard', 'content': 'hi'},
          ],
        }),
      );

      expect(response.status, HttpStatus.badRequest);
      expect(response.error?['message'], contains('wizard'));
    });

    test('a non-numeric temperature is rejected', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'POST',
        'http://127.0.0.1:$port/v1/chat/completions',
        body: jsonEncode({
          'temperature': 'hot',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      expect(response.status, HttpStatus.badRequest);
      expect(response.error?['param'], 'temperature');
    });

    test('a well-formed request still reports the model as unloaded',
        () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'POST',
        'http://127.0.0.1:$port/v1/chat/completions',
        body: jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      expect(response.status, HttpStatus.serviceUnavailable);
      expect(response.errorCode, 'model_not_loaded');
    });
  });

  group('routing', () {
    test('an unknown route returns an OpenAI-shaped 404', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.send(
        'GET',
        'http://127.0.0.1:$port/v1/embeddings',
      );

      expect(response.status, HttpStatus.notFound);
      expect(response.errorCode, 'not_found');
    });

    test('OPTIONS preflight succeeds without a key', () async {
      final port = await harness.startOnFreePort();

      final response = await harness.sendRaw(
        'OPTIONS',
        'http://127.0.0.1:$port/v1/chat/completions',
      );

      expect(response.status, HttpStatus.noContent);
      expect(response.headers['access-control-allow-origin'], '*');
    });
  });
}
