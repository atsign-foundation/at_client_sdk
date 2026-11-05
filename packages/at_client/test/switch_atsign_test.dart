import 'package:at_client/at_client_io.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';
import 'test_utils/hive_store.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

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
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(alicePreference),
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
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(alicePreference),
          atKeysIo: noKeysFor(aliceAtSign),
          storage: hiveStoreFor(aliceAtSign, alicePreference)));
      expect(atClientManager.atClient.getCurrentAtSign(), aliceAtSign);
      final bobPreference = AtClientPreference()..hiveStoragePath = 'test/hive';
      final bobAtSign = '@bob';
      atClientManager.use(await buildAtClient(
          atSign: bobAtSign,
          namespace: 'buzz',
          preference: bobPreference,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(bobPreference),
          atKeysIo: noKeysFor(bobAtSign),
          storage: hiveStoreFor(bobAtSign, bobPreference)));
      expect(atClientManager.atClient.getCurrentAtSign(), bobAtSign);
    });

    test(
        'when the app switches from Alice\'s client to Bob\'s, then each sync '
        'service keeps its own client\'s listeners', () async {
      final aliceAtSign = '@alice';
      final atClientManager = AtClientManager(aliceAtSign);
      final alicePreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive';
      final alice = await buildAtClient(
          atSign: aliceAtSign,
          namespace: 'wavi',
          preference: alicePreference,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(alicePreference),
          atKeysIo: noKeysFor(aliceAtSign),
          storage: hiveStoreFor(aliceAtSign, alicePreference));
      atClientManager.use(alice);
      final aliceSync = alice.syncService as SyncServiceImpl;
      aliceSync.addProgressListener(AliceSyncProgressListener());
      final bobPreference = AtClientPreference()..hiveStoragePath = 'test/hive';
      final bobAtSign = '@bob';
      final bob = await buildAtClient(
          atSign: bobAtSign,
          namespace: 'buzz',
          preference: bobPreference,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(bobPreference),
          atKeysIo: noKeysFor(bobAtSign),
          storage: hiveStoreFor(bobAtSign, bobPreference));
      atClientManager.use(bob);
      final bobSync = bob.syncService as SyncServiceImpl;
      bobSync.addProgressListener(BobSyncProgressListener());
      expect(atClientManager.atClient, same(bob));
      // NOTE: a stop marks the client stopped at once but empties its sync
      // service's listeners only after an await, which a synchronous switch
      // returns before.
      expect(alice.isStopped, isFalse,
          reason: 'the switch leaves Alice\'s client running');
      // NOTE: by identity rather than by count — the SDK registers a listener
      // of its own on every sync service, so a bare count says nothing about
      // whose app listeners a service holds.
      expect(
          aliceSync.progressListeners().whereType<AliceSyncProgressListener>(),
          hasLength(1),
          reason: 'her listener still hears her client\'s sync');
      expect(aliceSync.progressListeners().whereType<BobSyncProgressListener>(),
          isEmpty);
      expect(bobSync.progressListeners().whereType<BobSyncProgressListener>(),
          hasLength(1));
      expect(bobSync.progressListeners().whereType<AliceSyncProgressListener>(),
          isEmpty,
          reason: 'Alice\'s listener would be handed Bob\'s sync events');
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
