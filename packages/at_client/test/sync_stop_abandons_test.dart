import 'dart:async';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockAtClient extends Mock implements AtClient {}

class _MockLocalSecondary extends Mock implements LocalSecondary {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

void main() {
  setUpAll(() {
    registerFallbackValue(AtKey());
  });

  group('stop() during a round', () {
    late _MockAtClient atClient;
    late _MockLocalSecondary localSecondary;
    late SyncServiceImpl sync;

    setUp(() async {
      atClient = _MockAtClient();
      localSecondary = _MockLocalSecondary();
      when(() => atClient.getCurrentAtSign()).thenReturn('@abandon');
      when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
      final notifications = _MockNotificationService();
      when(() => notifications.subscribe(
              regex: any(named: 'regex'),
              shouldDecrypt: any(named: 'shouldDecrypt')))
          .thenAnswer((_) => const Stream<AtNotification>.empty());
      when(() => atClient.notificationService).thenReturn(notifications);
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
      sync = await SyncServiceImpl.create(atClient,
          remoteSecondary: _MockRemoteSecondary(),
          warmStartSync: false) as SyncServiceImpl;
    });

    test('the round ends at its next step and touches nothing further',
        () async {
      final gate = Completer<List<String>>();
      when(() => localSecondary.peekSyncQueue()).thenAnswer((_) => gate.future);
      when(() => atClient.get(any())).thenAnswer((_) async => AtValue());

      final round = sync.syncInternal(5, SyncRequest()..result = SyncResult(),
          localCommitIdBeforeSync: 1);
      await Future<void>.delayed(Duration.zero);
      await sync.stop();
      gate.complete(<String>[]);

      await expectLater(round, throwsA(isA<Exception>()),
          reason: 'a stopped service abandons the round rather than '
              'finishing it against storage that may be closing');
      verifyNever(() => atClient.get(any()));
    });

    test('the same round completes when not stopped (control)', () async {
      when(() => localSecondary.peekSyncQueue())
          .thenAnswer((_) async => <String>[]);
      when(() => atClient.get(any())).thenAnswer((_) async => AtValue());

      try {
        await sync.syncInternal(5, SyncRequest()..result = SyncResult(),
            localCommitIdBeforeSync: 1);
      } catch (_) {}
      verify(() => atClient.get(any())).called(greaterThan(0));
    });
  });

  test(
      'syncQueueSyncSnapshot is null for a closed queue, as for an unopened one',
      () async {
    final atClient = _MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn('@snapshot');
    final box =
        await Hive.openBox<String>('snapshot_probe', bytes: Uint8List(0));
    final queue = AtSyncQueue(atSign: '@snapshot');
    await queue.open(injectedBox: box);
    final ls = LocalSecondary(atClient, keyStore: null, syncQueue: queue);
    expect(ls.syncQueueSyncSnapshot, 0);
    await queue.close();
    expect(ls.syncQueueSyncSnapshot, isNull,
        reason: 'a closed queue has no size to report; null is what a caller '
            'already handles for a queue that never opened');
  });
}
