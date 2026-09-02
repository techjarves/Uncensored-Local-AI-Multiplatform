import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/services/wakelock_service.dart';

/// The wake lock is claimed independently by downloads, a loaded model and
/// the API server. Before reference counting, whichever finished first called
/// disable() and tore down the foreground service the others still needed.
///
/// These assert the bookkeeping only — the platform calls inside are no-ops
/// off-device, which is exactly what makes the bookkeeping worth testing.
void main() {
  late WakelockService service;

  setUp(() {
    service = WakelockService();
  });

  test('starts with no holders', () {
    expect(service.activeHolders, isEmpty);
  });

  test('a download claim is tracked', () async {
    await service.enableForDownload(modelName: 'Gemma 2 2B');

    expect(service.activeHolders, contains(WakelockService.holderDownload));
  });

  test('finishing a download does not release a loaded model', () async {
    await service.enableForInference(modelName: 'Gemma 2 2B');
    await service.enableForDownload();

    await service.releaseDownload();

    expect(
      service.activeHolders,
      contains(WakelockService.holderModel),
      reason: 'the loaded model still needs the device awake',
    );
    expect(
      service.activeHolders,
      isNot(contains(WakelockService.holderDownload)),
    );
  });

  test('stopping the API server does not release a loaded model', () async {
    await service.enableForInference();
    await service.enableForApiServer();

    await service.releaseApiServer();

    expect(service.activeHolders, contains(WakelockService.holderModel));
  });

  test('unloading a model does not release an in-flight download', () async {
    await service.enableForDownload();
    await service.enableForInference();

    await service.releaseModel();

    expect(service.activeHolders, contains(WakelockService.holderDownload));
  });

  test('the lock clears once every holder releases', () async {
    await service.enableForDownload();
    await service.enableForInference();
    await service.enableForApiServer();

    await service.releaseDownload();
    await service.releaseModel();
    expect(service.activeHolders, hasLength(1));

    await service.releaseApiServer();
    expect(service.activeHolders, isEmpty);
  });

  test('acquiring the same holder twice is idempotent', () async {
    await service.enableForDownload();
    await service.enableForDownload();

    expect(service.activeHolders, hasLength(1));

    await service.releaseDownload();
    expect(service.activeHolders, isEmpty);
  });

  test('releasing an unheld claim is harmless', () async {
    await service.releaseDownload();

    expect(service.activeHolders, isEmpty);
  });

  test('disable() drops every claim, for app teardown', () async {
    await service.enableForDownload();
    await service.enableForInference();
    await service.enableForApiServer();

    await service.disable();

    expect(service.activeHolders, isEmpty);
  });

  test('activeHolders is not modifiable by callers', () {
    expect(
      () => service.activeHolders.add('nope'),
      throwsUnsupportedError,
    );
  });
}
