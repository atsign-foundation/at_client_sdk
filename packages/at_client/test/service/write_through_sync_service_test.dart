import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/write_through_sync_service.dart';
import 'package:test/test.dart';

class _Recorder implements SyncProgressListener {
  final events = <SyncProgress>[];
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) =>
      events.add(syncProgress);
}

void main() {
  late WriteThroughSyncService service;

  setUp(() => service = WriteThroughSyncService('@writethrough'));

  test('is always in sync and never in progress', () async {
    expect(await service.isInSync(), isTrue);
    expect(service.isSyncInProgress, isFalse);
  });

  test('sync() reports success to onDone and to every listener', () async {
    final recorder = _Recorder();
    service.addProgressListener(recorder);
    SyncResult? result;

    // ignore: deprecated_member_use_from_same_package
    service.sync(onDone: (SyncResult r) => result = r);
    await pumpEventQueue();

    expect(result?.syncStatus, SyncStatus.success);
    expect(recorder.events.single.syncStatus, SyncStatus.success);
    expect(recorder.events.single.atSign, '@writethrough');
  });

  test('removed listeners hear nothing', () async {
    final recorder = _Recorder();
    service
      ..addProgressListener(recorder)
      ..removeProgressListener(recorder);

    service.sync();
    await pumpEventQueue();

    expect(recorder.events, isEmpty);
  });

  test('waitUntilCaughtUp completes at once', () async {
    await service.waitUntilCaughtUp(timeout: const Duration(seconds: 1));
  });
}
