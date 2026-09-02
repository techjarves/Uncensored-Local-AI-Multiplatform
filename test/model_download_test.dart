import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:portable_ai_flutter/models/ai_model_info.dart';
import 'package:portable_ai_flutter/services/model_manager.dart';

/// Regression tests for model download integrity.
///
/// Each test serves the payload from a real loopback HTTP server so the
/// manager exercises its actual streaming, resume and verification paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding installs an HttpOverrides that answers 400 to every
  // request. These tests talk to a real loopback server, so opt back out.
  HttpOverrides.global = null;

  late Directory tempDir;
  late Directory modelsDir;
  late ModelManager manager;
  late _FakeHost host;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ula-download-test-');
    modelsDir = Directory('${tempDir.path}/models');
    Hive.init(tempDir.path);
    await Hive.openBox('models_meta');

    manager = ModelManager();
    await manager.init(modelsDirOverride: modelsDir.path);

    host = await _FakeHost.start();
  });

  tearDown(() async {
    await host.stop();
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  AiModelInfo modelFor(String path, {String sha = ''}) => AiModelInfo(
    id: 'test-model',
    name: 'Test Model',
    filename: 'test-model.gguf',
    url: '${host.baseUrl}$path',
    sizeGb: 0.001,
    minRamGb: 1,
    label: 'CUSTOM',
    badge: '',
    systemPrompt: '',
    sha256: sha,
  );

  File finalFile() => File('${modelsDir.path}/test-model.gguf');
  File partFile() => File('${modelsDir.path}/test-model.gguf.part');

  group('response validation', () {
    test('a 404 is reported and leaves no .gguf behind', () async {
      host.respondNotFound('/missing.gguf');

      await expectLater(
        manager.downloadModel(modelFor('/missing.gguf')),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message',
              contains('404')),
        ),
      );

      expect(await finalFile().exists(), isFalse);
      expect(manager.downloadedModels, isEmpty);
    });

    test('a 403 explains that access was denied', () async {
      host.respondStatus('/gated.gguf', HttpStatus.forbidden);

      await expectLater(
        manager.downloadModel(modelFor('/gated.gguf')),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message',
              contains('denied')),
        ),
      );

      expect(await finalFile().exists(), isFalse);
    });

    test('an HTML login page is not saved as a model', () async {
      host.respondHtml('/login.gguf');

      await expectLater(
        manager.downloadModel(modelFor('/login.gguf')),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message',
              contains('web page')),
        ),
      );

      expect(await finalFile().exists(), isFalse);
    });
  });

  group('successful download', () {
    test('writes the file and registers it', () async {
      final payload = _payload(4096);
      host.respondBytes('/model.gguf', payload);

      await manager.downloadModel(modelFor('/model.gguf'));

      expect(await finalFile().exists(), isTrue);
      expect(await finalFile().readAsBytes(), payload);
      expect(manager.downloadedModels, contains('test-model.gguf'));
      expect(await partFile().exists(), isFalse);
    });

    test('a matching checksum passes verification', () async {
      final payload = _payload(4096);
      host.respondBytes('/model.gguf', payload);

      await manager.downloadModel(
        modelFor('/model.gguf', sha: sha256.convert(payload).toString()),
      );

      expect(await finalFile().exists(), isTrue);
    });
  });

  group('checksum verification', () {
    test('a corrupt download is rejected and discarded', () async {
      host.respondBytes('/model.gguf', _payload(4096));

      await expectLater(
        manager.downloadModel(
          modelFor('/model.gguf', sha: 'a' * 64),
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message',
              contains('integrity check')),
        ),
      );

      expect(await finalFile().exists(), isFalse);
      expect(await partFile().exists(), isFalse,
          reason: 'the bad partial must not be left to be resumed');
      expect(manager.downloadedModels, isEmpty);
    });
  });

  group('resume', () {
    test('a server honouring Range appends only the remainder', () async {
      final payload = _payload(8192);
      host.respondBytes('/model.gguf', payload, supportRange: true);

      // Simulate an interrupted transfer.
      await partFile().parent.create(recursive: true);
      await partFile().writeAsBytes(payload.sublist(0, 3000));

      await manager.downloadModel(modelFor('/model.gguf'));

      expect(await finalFile().readAsBytes(), payload,
          reason: 'resumed file must match the original byte for byte');
    });

    test('a server ignoring Range restarts cleanly instead of corrupting',
        () async {
      final payload = _payload(8192);
      // supportRange: false -> replies 200 with the whole body even though
      // the client asked for a byte range.
      host.respondBytes('/model.gguf', payload, supportRange: false);

      await partFile().parent.create(recursive: true);
      await partFile().writeAsBytes(payload.sublist(0, 3000));

      await manager.downloadModel(modelFor('/model.gguf'));

      final result = await finalFile().readAsBytes();
      expect(result.length, payload.length,
          reason: 'appending a full body to a partial would inflate the file');
      expect(result, payload);
    });
  });

  group('concurrent downloads', () {
    test('cancelling one download does not kill another', () async {
      final slow = _payload(2 * 1024 * 1024);
      final quick = _payload(4096);
      host.respondBytes('/slow.gguf', slow, throttle: true);
      host.respondBytes('/quick.gguf', quick);

      final slowModel = AiModelInfo(
        id: 'slow',
        name: 'Slow',
        filename: 'slow.gguf',
        url: '${host.baseUrl}/slow.gguf',
        sizeGb: 0.002,
        minRamGb: 1,
        label: 'CUSTOM',
        badge: '',
        systemPrompt: '',
      );

      final slowFuture = manager.downloadModel(slowModel).catchError((_) {});
      // Let the slow transfer get going, then cancel it.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      manager.cancelDownload('slow.gguf');
      await slowFuture;

      // The unrelated download must still complete normally.
      await manager.downloadModel(modelFor('/quick.gguf'));

      expect(await finalFile().readAsBytes(), quick);
      expect(manager.downloadedModels, contains('test-model.gguf'));
      expect(manager.downloadedModels, isNot(contains('slow.gguf')));
    });
  });
}

Uint8List _payload(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => i % 251));

/// A tiny configurable HTTP origin for the tests above.
class _FakeHost {
  final HttpServer _server;
  final Map<String, Future<void> Function(HttpRequest)> _routes = {};

  _FakeHost(this._server) {
    _server.listen((request) async {
      final handler = _routes[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      await handler(request);
    });
  }

  static Future<_FakeHost> start() async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    return _FakeHost(server);
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);

  void respondNotFound(String path) {
    _routes[path] = (request) async {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('not found');
      await request.response.close();
    };
  }

  void respondStatus(String path, int status) {
    _routes[path] = (request) async {
      request.response.statusCode = status;
      await request.response.close();
    };
  }

  void respondHtml(String path) {
    _routes[path] = (request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html><body>Please sign in</body></html>');
      await request.response.close();
    };
  }

  void respondBytes(
    String path,
    Uint8List body, {
    bool supportRange = false,
    bool throttle = false,
  }) {
    _routes[path] = (request) async {
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      var start = 0;

      if (supportRange && rangeHeader != null) {
        final match = RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader);
        if (match != null) {
          start = int.parse(match.group(1)!);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${body.length - 1}/${body.length}',
          );
        }
      } else {
        // Deliberately ignores Range and answers 200 with the whole body.
        request.response.statusCode = HttpStatus.ok;
      }

      final slice = body.sublist(start);
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.contentLength = slice.length;

      if (throttle) {
        const chunk = 16 * 1024;
        for (var i = 0; i < slice.length; i += chunk) {
          request.response.add(
            slice.sublist(i, (i + chunk).clamp(0, slice.length)),
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      } else {
        request.response.add(slice);
      }

      await request.response.close();
    };
  }
}

