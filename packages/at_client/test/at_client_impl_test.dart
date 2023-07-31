import 'package:at_client/at_client.dart';
import 'package:at_client/src/compaction/at_commit_log_compaction.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtCompactionJob extends Mock implements AtCompactionJob {
  bool isCronScheduled = false;

  @override
  void scheduleCompactionJob(AtCompactionConfig atCompactionConfig) {
    isCronScheduled = true;
  }

  @override
  Future<void> stopCompactionJob() async {
    isCronScheduled = false;
  }
}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockSecondaryKeystore extends Mock implements SecondaryKeyStore {}

void main() {
  group('A group of at client impl create tests', () {
    final String atSign = '@alice';
    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      AtClientManager.getInstance().removeAllChangeListeners();
    });
    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      AtClientManager.getInstance().removeAllChangeListeners();
    });

    test('test current atsign', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()..syncRegex = '.wavi';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      expect(atClient.getCurrentAtSign(), atSign);
    });
    test('test current atsign - backward compatibility', () async {
      final preference = AtClientPreference()..syncRegex = '.wavi';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference);
      expect(atClient.getCurrentAtSign(), atSign);
    });
    test('test preference', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()..syncRegex = '.wavi';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      expect(atClient.getPreferences()!.syncRegex, '.wavi');
    });
  });

  group('A group of tests on switch atSign event', () {
    String atSign = '@alice';
    String namespace = 'wavi';
    AtClientPreference atClientPreference = AtClientPreference();
    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      AtClientManager.getInstance().removeAllChangeListeners();
    });
    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      AtClientManager.getInstance().removeAllChangeListeners();
    });
    test('A test to verify switch atSign event clears the inactive listeners',
        () async {
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      expect(atClientManager.getChangeListenersSize(), 3);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign('@bob', namespace, atClientPreference);
      expect(atClientManager.getChangeListenersSize(), 3);
      // Verify the listeners in [AtClientManager._changeListeners] list belongs
      // to the new atSign. Here @bob.
      var itr = atClientManager.getItemsInChangeListeners();
      while (itr.moveNext()) {
        if (itr.current is NotificationService) {
          expect(
              (itr.current as NotificationServiceImpl).currentAtSign, '@bob');
        } else if (itr.current is SyncService) {
          expect((itr.current as SyncServiceImpl).currentAtSign, '@bob');
        } else if (itr.current is AtClientImpl) {
          expect((itr.current as AtClientImpl).getCurrentAtSign(), '@bob');
        }
      }
    });

    test(
        'A test to verify switch atSign event when switching between same atSign',
        () async {
      String atSign = '@alice';
      String namespace = 'wavi';
      AtClientPreference atClientPreference = AtClientPreference();
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      expect(atClientManager.getChangeListenersSize(), 3);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      expect(atClientManager.getChangeListenersSize(), 3);
      // Verify the listeners in [AtClientManager._changeListeners] list belongs
      // to the new atSign. Here @alice.
      var itr = atClientManager.getItemsInChangeListeners();
      while (itr.moveNext()) {
        if (itr.current is NotificationService) {
          expect(
              (itr.current as NotificationServiceImpl).currentAtSign, atSign);
        } else if (itr.current is SyncService) {
          expect((itr.current as SyncServiceImpl).currentAtSign, atSign);
        } else if (itr.current is AtClientImpl) {
          expect((itr.current as AtClientImpl).getCurrentAtSign(), atSign);
        }
      }
    });

    test('A test to verify atSigns switched multiple times', () async {
      String atSign1 = '@alice';
      String atSign2 = '@bob';
      String atSign3 = '@emoji';
      String namespace = 'wavi';
      AtClientPreference atClientPreference = AtClientPreference();
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign1, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign2, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign1, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign2, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign3, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign2, namespace, atClientPreference);

      // Verify the listeners in [AtClientManager._changeListeners] list belongs
      // to the new atSign. Here @bob.
      var itr = atClientManager.getItemsInChangeListeners();
      while (itr.moveNext()) {
        if (itr.current is NotificationService) {
          expect(
              (itr.current as NotificationServiceImpl).currentAtSign, atSign2);
        } else if (itr.current is SyncService) {
          expect((itr.current as SyncServiceImpl).currentAtSign, atSign2);
        } else if (itr.current is AtClientImpl) {
          expect((itr.current as AtClientImpl).getCurrentAtSign(), atSign2);
        }
      }
    });

    test('A test to verify atSigns switched between three different atSign',
        () async {
      String atSign1 = '@alice';
      String atSign2 = '@bob';
      String atSign3 = '@emoji';
      String namespace = 'wavi';
      AtClientPreference atClientPreference = AtClientPreference();
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign1, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign2, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign3, namespace, atClientPreference);
      // Verify the listeners in [AtClientManager._changeListeners] list belongs
      // to the new atSign. Here @bob.
      var itr = atClientManager.getItemsInChangeListeners();
      while (itr.moveNext()) {
        if (itr.current is NotificationService) {
          expect(
              (itr.current as NotificationServiceImpl).currentAtSign, atSign3);
        } else if (itr.current is SyncService) {
          expect((itr.current as SyncServiceImpl).currentAtSign, atSign3);
        } else if (itr.current is AtClientImpl) {
          expect((itr.current as AtClientImpl).getCurrentAtSign(), atSign3);
        }
      }
    });
  });

  group('A group of tests related to AtCommitLogCompaction', () {
    test('A test to verify AtCommitLogCompaction is scheduled and stopped', () {
      String atSign = '@bob';
      MockAtCompactionJob mockAtCompactionJob = MockAtCompactionJob();
      AtClientCommitLogCompaction atClientCommitLogCompaction =
          AtClientCommitLogCompaction.create(atSign, mockAtCompactionJob);
      atClientCommitLogCompaction.scheduleCompaction(1);
      expect(mockAtCompactionJob.isCronScheduled, true);
      atClientCommitLogCompaction.stopCompactionJob();
      expect(mockAtCompactionJob.isCronScheduled, false);
    });
  });

  group('AtClientImpl.ensureLowerCase() functionality checks', () {
    late AtClientManager manager;
    late AtClientImpl client;
    test('Test AtClientImpl.ensureLowerCase() on an AtKey with no namespace',
        () async {
      AtKey key = AtKey()
        ..key = 'dummy'
        ..sharedBy = '@sender'
        ..sharedWith = '@receiver';

      manager = await AtClientManager.getInstance()
          .setCurrentAtSign('@sender', null, AtClientPreference());
      client = manager.atClient as AtClientImpl;

      //AtClientImpl.ensureLowerCase() has a void return type
      //this test is only to ensure that when this method is run
      //with an AtKey with namespace 'null', it does not throw an exception
      expect(client.ensureLowerCase(key), null);
      //this test is considered to be passing when the method does not throw
      // an exception/error while executing
    });

    test(
        'Test for AtClientImpl.ensureLowerCase() on an AtKey with upper case chars in namespace',
        () async {
      AtKey key = AtKey()
        ..key = 'lowercase'
        ..namespace = 'cAsEsEnSiTiVe'
        ..sharedBy = '@sender'
        ..sharedWith = '@receiver';

      //AtClientImpl.ensureLowerCase() has a void return type
      expect(client.ensureLowerCase(key), null); //errorless execution test
      expect(key.namespace,
          'casesensitive'); //namespace should be converted to lower case
    });

    test(
        'Test AtClientImpl.ensureLowerCase() on an AtKey with upper case chars in key and namespace',
        () async {
      AtKey key = AtKey()
        ..key = 'uPpErCasE'
        ..namespace = 'cAsEsEnSiTiVe'
        ..sharedBy = '@sender'
        ..sharedWith = '@receiver';

      //AtClientImpl.ensureLowerCase() has a void return type
      expect(client.ensureLowerCase(key), null); //errorless execution test
      expect(key.namespace,
          'casesensitive'); //namespace should be converted to lower case
      expect(key.key, 'uppercase'); //key should be converted to lower case
    });
  });

  group('Group of tests verify client behaviour on remote secondary reset', () {
    registerFallbackValue(MockRemoteSecondary());
    registerFallbackValue(LookupVerbBuilder());

    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    SecondaryKeyStore mockKeystore = MockSecondaryKeystore();
    AtClient client;

    test('Verify isSecondaryReset() functionality - negative case', () async {
      AtData responseObj = AtData()..data = 'incorrectLocalEncPublicKey';
      when(() => mockRemoteSecondary.executeVerb(any())).thenAnswer(
          (invocation) => Future.value('data:incorrectRemoteEncPublicKey'));
      when(() => mockKeystore.get(any()))
          .thenAnswer((invocation) => Future.value(responseObj));

      client = await AtClientImpl.create('@alice47', 'resetLocalTest',
          AtClientPreference()..isLocalStoreRequired = true,
          remoteSecondary: mockRemoteSecondary,
          localSecondaryKeyStore: mockKeystore);
      expect(await client.isSecondaryReset(), true);
    });

    test('Verify isSecondaryReset() functionality - positive case', () async {
      AtData responseObj = AtData()..data = 'correctEncPublicKey';
      when(() => mockRemoteSecondary.executeVerb(any()))
          .thenAnswer((invocation) => Future.value('data:correctEncPublicKey'));
      when(() => mockKeystore.get(any()))
          .thenAnswer((invocation) => Future.value(responseObj));

      client = await AtClientImpl.create('@alice47', 'resetLocalTest',
          AtClientPreference()..isLocalStoreRequired = true,
          remoteSecondary: mockRemoteSecondary,
          localSecondaryKeyStore: mockKeystore);
      expect(await client.isSecondaryReset(), false);
    });
  });
}
