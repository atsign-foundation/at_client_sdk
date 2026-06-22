import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/test_utils.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

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
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      expect(atClient.getCurrentAtSign(), atSign);
    });
    test('test current atsign - backward compatibility', () async {
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference);
      expect(atClient.getCurrentAtSign(), atSign);
    });
    test('test preference', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      expect(atClient.getPreferences()!.syncRegex, '.wavi');
    });
  });

  group('A group of tests on switch atSign event', () {
    String atSign = '@alice';
    String namespace = 'wavi';
    AtClientPreference atClientPreference = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      AtClientManager.getInstance().removeAllChangeListeners();
    });

    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      AtClientManager.getInstance().removeAllChangeListeners();
    });

    test('A test to verify change', () async {
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);

      expect(atClientManager.getChangeListenersSize(), 0);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign('@bob', namespace, atClientPreference);
      expect(atClientManager.getChangeListenersSize(), 0);

      // Notification Service, Sync Service and AtClientImpl do not register
      // change listeners anymore
    });

    test(
        'A test to verify switch atSign event when switching between same atSign',
        () async {
      String atSign = '@alice';
      String namespace = 'wavi';
      AtClientPreference atClientPreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);

      expect(atClientManager.getChangeListenersSize(), 0);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference);
      expect(atClientManager.getChangeListenersSize(), 0);

      // Notification Service, Sync Service and AtClientImpl do not register
      // change listeners anymore
    });

    test('A test to verify atSigns switched multiple times', () async {
      String atSign1 = '@alice';
      String atSign2 = '@bob';
      String atSign3 = '@emoji';
      String namespace = 'wavi';
      AtClientPreference atClientPreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
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
          expect((itr.current as NotificationServiceImpl).atSign, atSign2);
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
      AtClientPreference atClientPreference = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
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
          expect((itr.current as NotificationServiceImpl).atSign, atSign3);
        } else if (itr.current is SyncService) {
          expect((itr.current as SyncServiceImpl).currentAtSign, atSign3);
        } else if (itr.current is AtClientImpl) {
          expect((itr.current as AtClientImpl).getCurrentAtSign(), atSign3);
        }
      }
    });
  });

  group('AtClientImpl.ensureLowerCase() functionality checks', () {
    late AtClientManager manager;
    late AtClientImpl client;
    AtClientPreference pref = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';
    test('Test AtClientImpl.ensureLowerCase() on an AtKey with no namespace',
        () async {
      AtKey key = AtKey()
        ..key = 'dummy'
        ..sharedBy = '@sender'
        ..sharedWith = '@receiver';

      manager = await AtClientManager.getInstance()
          .setCurrentAtSign('@sender', null, pref);
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

  group('A group of tests related to apkam/enrollments', () {
    AtClientPreference pref = AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';
    test(
        'A test to verify enrollmentId is set in atClient after calling setCurrentAtSign',
        () async {
      final testEnrollmentId = 'abc123';
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign('@alice', 'wavi', pref,
              enrollmentId: testEnrollmentId);
      expect(atClientManager.atClient.enrollmentId, testEnrollmentId);
    });

    MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();

    test('verify behaviour of fetchEnrollmentRequests()', () async {
      String currentAtsign = '@apkam';
      String enrollKey1 =
          '0acdeb4d-1a2e-43e4-93bd-378f1d366ea7.new.enrollments.__manage$currentAtsign';
      String enrollValue1 =
          '{"appName":"buzz","deviceName":"pixel","namespace":{"buzz":"rw"}}';
      String enrollKey2 =
          '9beefa26-3384-4f10-81a6-0deaa4332669.new.enrollments.__manage$currentAtsign';
      String enrollValue2 =
          '{"appName":"buzz","deviceName":"pixel","namespace":{"buzz":"rw"}}';
      String enrollKey3 =
          'a6bbef17-c7bf-46f4-a172-1ed7b3b443bc.new.enrollments.__manage$currentAtsign';
      String enrollValue3 =
          '{"appName":"buzz","deviceName":"pixel","namespace":{"buzz":"rw"}}';
      when(() =>
          mockRemoteSecondary.executeCommand('enroll:list\n',
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2,"$enrollKey3":$enrollValue3}'));

      AtClient? client = await AtClientImpl.create(currentAtsign, 'buzz', pref,
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, AtEnrollment.create());
      AtClientImpl? clientImpl = client as AtClientImpl;

      List<Enrollment> requests =
          await clientImpl.enrollmentService!.fetchEnrollmentRequests();
      expect(requests.length, 3);
      expect(requests[0].enrollmentId,
          enrollKey1.substring(0, enrollKey1.indexOf('.')));
      expect(requests[0].appName, jsonDecode(enrollValue1)['appName']);
      expect(requests[0].deviceName, jsonDecode(enrollValue1)['deviceName']);
      expect(requests[0].namespace, jsonDecode(enrollValue1)['namespace']);

      expect(requests[1].enrollmentId,
          enrollKey2.substring(0, enrollKey1.indexOf('.')));
      expect(requests[1].appName, jsonDecode(enrollValue2)['appName']);
      expect(requests[1].deviceName, jsonDecode(enrollValue2)['deviceName']);
      expect(requests[1].namespace, jsonDecode(enrollValue2)['namespace']);

      expect(requests[2].enrollmentId,
          enrollKey3.substring(0, enrollKey1.indexOf('.')));
      expect(requests[2].appName, jsonDecode(enrollValue3)['appName']);
      expect(requests[2].deviceName, jsonDecode(enrollValue3)['deviceName']);
      expect(requests[2].namespace, jsonDecode(enrollValue3)['namespace']);
    });
  });

  group('A group of tests related to set SPP', () {
    String atSign = '@alice';
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    test(
        'A test to verify exception is thrown when SPP contains special characters',
        () async {
      String invalidSPP = 'abc#12';
      var atClientManager =
          await AtClientManager.getInstance().setCurrentAtSign(
              atSign,
              'wavi',
              AtClientPreference()
                ..hiveStoragePath = 'test/hive'
                ..commitLogPath = 'test/hive/path');
      expect(
          () async => await atClientManager.atClient.setSPP(invalidSPP),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message == '$invalidSPP is not a valid SPP')));
    });

    test(
        'A test to verify exception is thrown when SPP exceeds the character length',
        () async {
      String invalidSPP = 'abc1234';
      AtClientPreference pref = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, 'wavi', pref);
      expect(
          () async => await atClientManager.atClient.setSPP(invalidSPP),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message == '$invalidSPP should be 6 characters')));
    });

    test('A test to verify SPP is created successfully', () async {
      AtClientPreference pref = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', pref,
          remoteSecondary: mockRemoteSecondary);

      when(() => mockRemoteSecondary.executeCommand(
          any(that: startsWith('otp:put:ABC123')),
          auth: true)).thenAnswer((_) async => await Future.value('data:ok'));

      AtResponse atResponse =
          await atClient.setSPP('ABC123', expiry: AtClient.defaultSppExpiry);
      expect(atResponse.response, 'ok');
    });
    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
    });
  });
  group('A group of test to validate max length of a key', () {
    MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    test('test max length for put method', () async {
      AtClientPreference pref = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      AtClient? client = await AtClientImpl.create('@alice', 'buzz', pref,
          remoteSecondary: mockRemoteSecondary);
      var key = TestUtils.createRandomString(250);
      var atKey = AtKey.fromString('$key@alice');

      expect(
          () async => await client.put(atKey, 'hello'),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message ==
                  'Key length exceeds maximum permissible length of 248 characters')));
    });
  });

  group(
      'A group of tests to validate AtClient registers providers in CryptoRegistry',
      () {
    MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    MockLocalSecondary mockLocalSecondary = MockLocalSecondary();
    MockAtChopsKeys mockAtChopsKeys = MockAtChopsKeys();
    setUp(() {
      AtClientImpl.atClientInstanceMap.remove('@alice');
      var key = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
      registerFallbackValue(FakeLookupVerbBuilder());
      when(() => mockLocalSecondary.executeVerb(any()))
          .thenAnswer((_) => Future.value('yuh'));
      when(() => mockRemoteSecondary.executeVerb(any()))
          .thenAnswer((_) => Future.value('yuh'));
      when(() => mockAtChopsKeys.selfEncryptionKey).thenReturn(AESKey(key));
    });
    test('defaults to the legacy crypto config when none is configured',
        () async {
      AtClientPreference preferences = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path';
      AtChops chops = AtChopsImpl(mockAtChopsKeys);
      AtClient ac = await AtClientImpl.create(
        '@alice',
        'buzz',
        preferences,
        remoteSecondary: mockRemoteSecondary,
        atChops: chops,
      );
      // No crypto config => the legacy default. The built-in legacy provider is
      // the runtime's fallback (resolution itself is covered in
      // crypto_runtime_test), so it is intentionally not in the config list.
      final config = ac.getPreferences()?.crypto;
      expect(config?.defaultProviderId, 'legacy');
      expect(config?.lookup('legacy'), isNull);
      expect(config?.lookup('bubblesort'), isNull);
    });

    test('registers configured crypto providers during at_client creation',
        () async {
      final provider = _RecordingCryptoProvider('test-provider');
      AtClientPreference preferences = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path'
        ..crypto = CryptoConfig(
          defaultProviderId: 'test-provider',
          providers: [provider],
        );
      AtChops chops = AtChopsImpl(mockAtChopsKeys);

      AtClient ac = await AtClientImpl.create(
        '@alice',
        'buzz',
        preferences,
        remoteSecondary: mockRemoteSecondary,
        atChops: chops,
      );

      expect(ac.getPreferences()?.crypto.lookup('test-provider'),
          isA<CryptoProvider>());
    });

    test('throws when configured default crypto provider is not registered',
        () async {
      AtClientPreference preferences = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/path'
        ..crypto = const CryptoConfig(
          defaultProviderId: 'missing-provider',
        );
      AtChops chops = AtChopsImpl(mockAtChopsKeys);

      await expectLater(
        () => AtClientImpl.create(
          '@alice',
          'buzz',
          preferences,
          remoteSecondary: mockRemoteSecondary,
          atChops: chops,
        ),
        throwsA(isA<CryptoProviderNotRegistered>()),
      );
    });

    test(
        'adopts the new crypto config when a cached AtClient is re-used with '
        'an updated preference', () async {
      AtChops chops = AtChopsImpl(mockAtChopsKeys);

      // First creation registers only the legacy provider.
      AtClient ac1 = await AtClientImpl.create(
        '@alice',
        'buzz',
        AtClientPreference()
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/path'
          ..crypto = const CryptoConfig(defaultProviderId: 'legacy'),
        remoteSecondary: mockRemoteSecondary,
        atChops: chops,
      );
      expect(ac1.getPreferences()?.crypto.lookup('late-provider'), isNull);

      // Re-creating the same atSign re-uses the cached instance; the new
      // preference's crypto config is adopted onto it (no rebuild).
      final provider = _RecordingCryptoProvider('late-provider');
      AtClient ac2 = await AtClientImpl.create(
        '@alice',
        'buzz',
        AtClientPreference()
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/path'
          ..crypto = CryptoConfig(
            defaultProviderId: 'legacy',
            providers: [provider],
          ),
        remoteSecondary: mockRemoteSecondary,
        atChops: chops,
      );

      expect(identical(ac1, ac2), true);
      expect(ac2.getPreferences()?.crypto.lookup('late-provider'),
          isA<CryptoProvider>());
    });
  });
}

class _RecordingCryptoProvider extends CryptoProvider {
  @override
  final String id;

  _RecordingCryptoProvider(this.id);

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return value;
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    return value;
  }
}
