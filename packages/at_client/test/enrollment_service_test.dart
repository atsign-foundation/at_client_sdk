import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/test_utils.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockSyncService extends Mock implements SyncService {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

void main() {
  String currentAtSign = '@alice';
  String sharedWithAtSign = '@bob';
  late AtClient atClient;
  MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  String enrollmentId = 'abc123';

  setUpAll(() async {
    AtChops atChops = await TestUtils.getAtChops();
    atClient = await AtClientImpl.create(
        currentAtSign,
        'wavi',
        AtClientPreference()
          ..isLocalStoreRequired = true
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/commit',
        enrollmentId: enrollmentId,
        atChops: atChops,
        remoteSecondary: mockRemoteSecondary);
    atClient.syncService = MockSyncService();

    String key = '$enrollmentId.new.enrollments.__manage$currentAtSign';
    AtData atData = AtData()
      ..data = jsonEncode(Enrollment()
        ..appName = 'wavi'
        ..deviceName = 'iphone'
        ..namespace = {'wavi': 'rw'}
        ..enrollmentId = enrollmentId);

    // Store enrollment data
    await atClient.getLocalSecondary()?.keyStore?.put(key, atData);

    AtEncryptionResult? atEncryptionResult = atClient.atChops?.encryptString(
        atChops.atChopsKeys.selfEncryptionKey!.key, EncryptionKeyType.rsa2048);

    // Store "currentAtSign" encrypted symmetric key : shared_key.bob@alice
    await atClient.getLocalSecondary()?.keyStore?.put(
        'shared_key.bob$currentAtSign',
        AtData()..data = atEncryptionResult?.result);

    // Store the "sharedWith" atsign's encrypted shared key: @bob:shared_key@alice
    await atClient.getLocalSecondary()?.keyStore?.put(
        '$sharedWithAtSign:shared_key$currentAtSign',
        AtData()..data = atEncryptionResult?.result);
    // Store the "sharedWith" atSign's encryption public key cached in current atSign
    await atClient.getLocalSecondary()?.keyStore?.put(
        'cached:public:publickey$sharedWithAtSign',
        AtData()
          ..data =
              atChops.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey);

    // Store cached sharedkey
    await atClient.getLocalSecondary()?.keyStore?.put(
        'cached:@alice:shared_key@bob',
        AtData()..data = atEncryptionResult?.result);

    // Store cached sharedkey
    await atClient.getLocalSecondary()?.keyStore?.put(
        'public:publickey@alice',
        AtData()
          ..data =
              atChops.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey);
  });

  group('A group of tests related to apkam/enrollments', () {
    test(
        'A test to verify enrollmentId is set in atClient after calling setCurrentAtSign',
        () async {
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign('@alice', 'wavi', AtClientPreference(),
              enrollmentId: enrollmentId);
      expect(atClientManager.atClient.enrollmentId, enrollmentId);
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
      String enrollListCommand = (EnrollVerbBuilder()
            ..operation = EnrollOperationEnum.list)
          .buildCommand();
      when(() =>
          mockRemoteSecondary.executeCommand(enrollListCommand,
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2,"$enrollKey3":$enrollValue3}'));

      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'buzz', AtClientPreference(),
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, atAuthBase.atEnrollment(currentAtsign));
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

    test(
        'verify behaviour of fetchEnrollmentRequests() with enrollmentStatusFilter: [pending, approved]',
        () async {
      String currentAtsign = '@apkam1234';
      String enrollKey1 =
          '0acdeb4d-1a2e-43e4-93bd-random123.new.enrollments.__manage$currentAtsign';
      String enrollValue1 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      String enrollKey2 =
          '9beefa26-3384-4f10-81a6-random234.new.enrollments.__manage$currentAtsign';
      String enrollValue2 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      when(() =>
          mockRemoteSecondary.executeCommand(
              'enroll:list:{"enrollmentStatusFilter":["pending","approved"]}\n',
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2}'));

      EnrollmentListRequestParam listRequestParam = EnrollmentListRequestParam()
        ..enrollmentListFilter = [
          EnrollmentStatus.pending,
          EnrollmentStatus.approved
        ];
      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'random_namespace', AtClientPreference(),
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, atAuthBase.atEnrollment(currentAtsign));
      AtClientImpl? clientImpl = client as AtClientImpl;

      List<Enrollment> requests = await clientImpl.enrollmentService!
          .fetchEnrollmentRequests(enrollmentListParams: listRequestParam);
      expect(requests.length, 2);
      expect(requests[0].enrollmentId,
          enrollKey1.substring(0, enrollKey1.indexOf('.')));
      expect(requests[0].appName, jsonDecode(enrollValue1)['appName']);
      expect(requests[0].deviceName, jsonDecode(enrollValue1)['deviceName']);
      expect(requests[0].namespace, jsonDecode(enrollValue1)['namespace']);

      expect(requests[1].enrollmentId,
          enrollKey2.substring(0, enrollKey2.indexOf('.')));
      expect(requests[1].appName, jsonDecode(enrollValue2)['appName']);
      expect(requests[1].deviceName, jsonDecode(enrollValue2)['deviceName']);
      expect(requests[1].namespace, jsonDecode(enrollValue2)['namespace']);
    });

    test(
        'verify behaviour of fetchEnrollmentRequests() with enrollmentStatusFilter: [approved]',
        () async {
      String currentAtsign = '@apkam1234';
      String enrollKey1 =
          '0acdeb4d-1a2e-43e4-93bd-randomabc.new.enrollments.__manage$currentAtsign';
      String enrollValue1 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      String enrollKey2 =
          '9beefa26-3384-4f10-81a6-randomcde.new.enrollments.__manage$currentAtsign';
      String enrollValue2 =
          '{"appName":"unit_test","deviceName":"testDevice","namespace":{"random_namespace":"rw"}}';
      when(() =>
          mockRemoteSecondary.executeCommand(
              'enroll:list:{"enrollmentStatusFilter":["approved"]}\n',
              auth: true)).thenAnswer((_) => Future.value('data:{"$enrollKey1":'
          '$enrollValue1,"$enrollKey2":$enrollValue2}'));

      EnrollmentListRequestParam listRequestParam = EnrollmentListRequestParam()
        ..enrollmentListFilter = [EnrollmentStatus.approved];
      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'random_namespace_1', AtClientPreference(),
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, atAuthBase.atEnrollment(currentAtsign));
      AtClientImpl? clientImpl = client as AtClientImpl;

      List<Enrollment> requests = await clientImpl.enrollmentService!
          .fetchEnrollmentRequests(enrollmentListParams: listRequestParam);
      expect(requests.length, 2);
      expect(requests[0].enrollmentId,
          enrollKey1.substring(0, enrollKey1.indexOf('.')));
      expect(requests[0].appName, jsonDecode(enrollValue1)['appName']);
      expect(requests[0].deviceName, jsonDecode(enrollValue1)['deviceName']);
      expect(requests[0].namespace, jsonDecode(enrollValue1)['namespace']);

      expect(requests[1].enrollmentId,
          enrollKey2.substring(0, enrollKey2.indexOf('.')));
      expect(requests[1].appName, jsonDecode(enrollValue2)['appName']);
      expect(requests[1].deviceName, jsonDecode(enrollValue2)['deviceName']);
      expect(requests[1].namespace, jsonDecode(enrollValue2)['namespace']);
    });
  });

  group(
      'A group of tests related to put operation when authenticated with apkam',
      () {
    test(
        'A test to verify put operation is successful for the authorized namespace',
        () async {
      AtKey atKey =
          (AtKey.shared('phone')..sharedWith(sharedWithAtSign)).build();
      bool putResponse = await atClient.put(atKey, '1234');
      expect(putResponse, true);
    });

    test(
        'A test to verify get operation is successful for the authorized namespace',
        () async {
      AtEncryptionResult? encryptedValue = atClient.atChops?.encryptString(
          '1234', EncryptionKeyType.aes256,
          iv: AtChopsUtil.generateIVLegacy());
      FakeLookupVerbBuilder fakeLookupVerbBuilder = FakeLookupVerbBuilder();
      registerFallbackValue(fakeLookupVerbBuilder);
      when(() => mockRemoteSecondary.executeVerb(any(that: LookupKeyMatcher())))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'data': encryptedValue?.result,
                    'key': '$currentAtSign:phone.wavi$sharedWithAtSign'
                  })}'));
      AtKey atKey = AtKey()
        ..key = 'phone'
        ..sharedBy = sharedWithAtSign
        ..namespace = 'wavi';
      AtValue atValue = await atClient.get(atKey);
      expect(atValue.value, '1234');
    });
  });

  group(
      'A group of tests related to enrollment authorization with read allowed',
      () {
    test('test llookup on cached:@bob:shared_key@alice', () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'cached:@bob:shared_key@alice', LLookupVerbBuilder());
      expect(authorized, true);
    });

    test('test llookup on cached public key', () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'cached:public:phone.fubar@alice', LLookupVerbBuilder());
      expect(authorized, true);
    });

    test(
        'test get on shared key with read-write access with unauthorized namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.unauth@alice', LookupVerbBuilder());
      expect(authorized, false);
    });

    test('test get on shared key with read access with enrolled namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "r"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.fubar@alice', LookupVerbBuilder());
      expect(authorized, true);
    });

    test('test scan on shared key with read access with unauthorized namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "r"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.unauth@alice', ScanVerbBuilder());
      expect(authorized, false);
    });
  });

  group(
      'A group of tests related to enrollment authorization with read-write allowed',
      () {
    test(
        'test update on shared key with only read access to enrollment namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "r"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.fubar@alice', UpdateVerbBuilder());
      expect(authorized, false);
    });

    test(
        'test update on shared key with read-write access to enrollment namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.fubar@alice', UpdateVerbBuilder());
      expect(authorized, true);
    });

    test(
        'test update on shared key with read-write access with unauthorized namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.unauth@alice', UpdateVerbBuilder());
      expect(authorized, false);
    });

    test(
        'test update on public key with read-write access to enrollment namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'public:phone.fubar@alice', UpdateVerbBuilder());
      expect(authorized, true);
    });

    test(
        'test update on public key with read-write access with unauthorized namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'public:phone.unauth@alice', UpdateVerbBuilder());
      expect(authorized, false);
    });

    test(
        'test notify on shared key with read-write access with enrolled namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'public:phone.fubar@alice', NotifyVerbBuilder());
      expect(authorized, true);
    });

    test('test notify on shared key with read access with enrolled namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "r"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'public:phone.fubar@alice', NotifyVerbBuilder());
      expect(authorized, false);
    });

    test(
        'test notify on shared key with read-write access with unauthorized namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          'public:phone.unauth@alice', NotifyVerbBuilder());
      expect(authorized, false);
    });

    test(
        'test delete on shared key with read-write access with enrolled namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "rw"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.fubar@alice', DeleteVerbBuilder());
      expect(authorized, true);
    });

    test('test delete on shared key with read access with enrolled namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "r"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.fubar@alice', DeleteVerbBuilder());
      expect(authorized, false);
    });

    test(
        'test delete on shared key with read-write access with unauthorized namespace',
        () async {
      final testEnrollmentId = 'aaa111';
      LocalSecondary ls = LocalSecondary(atClient);

      ls.enrollment = Enrollment()
        ..enrollmentId = testEnrollmentId
        ..appName = 'testApkamAuthCachedLLookup'
        ..deviceName = 'testDevice'
        ..namespace = {"fubar": "r"};

      final bool authorized = await ls.isEnrollmentAuthorizedForOperation(
          '@bob:phone.unauth@alice', DeleteVerbBuilder());
      expect(authorized, false);
    });
  });
}

class LookupKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description.add(
      'A custom matcher to match the encrypted shared key for update verb builder');

  @override
  bool matches(item, Map matchState) {
    if (item is LookupVerbBuilder && item.atKey.key.contains('phone')) {
      return true;
    }
    return false;
  }
}
