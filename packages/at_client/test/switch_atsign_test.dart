import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';
import 'test_utils/hive_store.dart';
import 'test_utils/no_keys.dart';

void main() {
  group('A group of switch atsign tests', () {
    tearDown(() async {
      for (final client
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await client.stop();
      }
    });

    test('Test that we can inject an AtLookUp instance', () async {
      final aliceAtSign = '@alice';
      final alicePreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive';
      final mockAtLookUp = MockAtLookUp();
      // The real RemoteSecondary wraps this lookup, and closing the client
      // closes the lookup - so an unstubbed close() answers null into the
      // Future<void> the teardown awaits.
      when(() => mockAtLookUp.close()).thenAnswer((_) async {});
      final atClient = await buildAtClient(
          atSign: aliceAtSign,
          namespace: 'wavi',
          preference: alicePreference,
          atKeysIo: noKeysFor(aliceAtSign),
          atLookUp: mockAtLookUp,
          storage: hiveStoreFor(aliceAtSign, alicePreference));
      expect(atClient.getCurrentAtSign(), aliceAtSign);
      expect(atClient.getRemoteSecondary()!.atLookUp, mockAtLookUp);
      expect(atClient.getRemoteSecondary()!.atLookUp.runtimeType, MockAtLookUp);
    });

    test('test switch atsign - check atsign name', () async {
      final aliceAtSign = '@alice';
      final atClientManager = AtClientManager(aliceAtSign);
      final alicePreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive';
      atClientManager.use(await buildAtClient(
          atSign: aliceAtSign,
          namespace: 'wavi',
          preference: alicePreference,
          atKeysIo: noKeysFor(aliceAtSign),
          storage: hiveStoreFor(aliceAtSign, alicePreference)));
      expect(atClientManager.atClient.getCurrentAtSign(), aliceAtSign);
      final bobPreference = AtClientPreference()..hiveStoragePath = 'test/hive';
      final bobAtSign = '@bob';
      atClientManager.use(await buildAtClient(
          atSign: bobAtSign,
          namespace: 'buzz',
          preference: bobPreference,
          atKeysIo: noKeysFor(bobAtSign),
          storage: hiveStoreFor(bobAtSign, bobPreference)));
      expect(atClientManager.atClient.getCurrentAtSign(), bobAtSign);
    });

    test('test switch atsign - check progress listener cleared', () async {
      final aliceAtSign = '@alice';
      final atClientManager = AtClientManager(aliceAtSign);
      final alicePreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive';
      atClientManager.use(await buildAtClient(
          atSign: aliceAtSign,
          namespace: 'wavi',
          preference: alicePreference,
          atKeysIo: noKeysFor(aliceAtSign),
          storage: hiveStoreFor(aliceAtSign, alicePreference)));
      expect(atClientManager.atClient.getCurrentAtSign(), aliceAtSign);
      atClientManager.atClient.syncService
          .addProgressListener(AliceSyncProgressListener());
      final bobPreference = AtClientPreference()..hiveStoragePath = 'test/hive';
      final bobAtSign = '@bob';
      atClientManager.use(await buildAtClient(
          atSign: bobAtSign,
          namespace: 'buzz',
          preference: bobPreference,
          atKeysIo: noKeysFor(bobAtSign),
          storage: hiveStoreFor(bobAtSign, bobPreference)));
      atClientManager.atClient.syncService
          .addProgressListener(BobSyncProgressListener());
      expect(atClientManager.atClient.getCurrentAtSign(), bobAtSign);
      // NOTE: by identity rather than by count — the SDK registers a listener
      // of its own on every sync service, so a bare count says nothing about
      // whose app listeners survived the switch.
      final listeners =
          (atClientManager.atClient.syncService as SyncServiceImpl)
              .progressListeners();
      expect(listeners.whereType<BobSyncProgressListener>(), hasLength(1));
      expect(listeners.whereType<AliceSyncProgressListener>(), isEmpty,
          reason: 'the previous atSign\'s listener must not carry over — it '
              'would be handed the new atSign\'s sync events');
    });
  });
}

class AliceSyncProgressListener implements SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    print('alice listener event ${syncProgress.toString()}');
  }

  @override
  String toString() {
    return 'AliceSyncProgressListener';
  }
}

class BobSyncProgressListener implements SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    print('bob listener event ${syncProgress.toString()}');
  }

  @override
  String toString() {
    return 'BobSyncProgressListener';
  }
}
