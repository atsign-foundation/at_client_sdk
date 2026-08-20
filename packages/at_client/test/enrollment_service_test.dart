import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/test_utils.dart';
import 'test_utils/mocks.dart';

/// Records the decision at_client hands down to at_auth, which is where the
/// choice between minting a symmetric key and passing the enrollee's own one
/// through becomes observable.
class RecordingAtEnrollment extends Mock implements AtEnrollment {
  final List<EnrollmentRequestDecision> approvals = [];

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision decision, AtLookUp atLookUp,
      {AtChops? approverChops}) async {
    approvals.add(decision);
    return AtEnrollmentResponse(
        decision.enrollmentId, EnrollmentStatus.approved);
  }
}

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
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/commit',
        enrollmentId: enrollmentId,
        atChops: atChops,
        remoteSecondary: mockRemoteSecondary);
    atClient.syncService = MockSyncService();

    // The `enroll:fetch` this client makes the first time something asks what
    // it is authorized for.
    //
    // ⚠️ This used to seed a keystore entry at `local:<enrollmentId><atSign>`
    // instead. Nothing in production writes that key, so the seed stood for a
    // state the SDK never reaches and the fetch-and-parse path below was never
    // exercised. Stubbing the command drives the real one.
    when(() => mockRemoteSecondary
        .executeCommand('enroll:fetch:{"enrollmentId":"$enrollmentId"}\n',
            auth: true)).thenAnswer((_) async => 'data:${jsonEncode({
              'appName': 'wavi',
              'deviceName': 'iphone',
              'namespace': {'wavi': 'rw'},
            })}');

    AtEncryptionResult? atEncryptionResult = await atClient.atChops
        ?.encryptString(atChops.atChopsKeys.selfEncryptionKey!.key,
            EncryptionKeyType.rsa2048);

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

    // Store cached shared_key
    await atClient.getLocalSecondary()?.keyStore?.put(
        'cached:@alice:shared_key@bob',
        AtData()..data = atEncryptionResult?.result);

    // Store cached shared_key
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
      var pref = AtClientPreference()
        ..hiveStoragePath = "test/hive"
        ..commitLogPath = "test/hive/commit";
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign('@alice', 'wavi', pref, enrollmentId: enrollmentId);
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
      AtClientPreference pref = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
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

    test('fetchEnrollmentRequests carries the advertised key package',
        () async {
      // The metadata the enrolling app put on its enroll:request, stored
      // verbatim by the atServer. It was being dropped on the floor here,
      // which is why conveyance used to re-discover the package over
      // enroll:listns instead of reading the request it was approving.
      // A distinct atSign: AtClientImpl.create caches per atSign, so reusing
      // one another test already built would hand back that test's client and
      // its mock secondary, and this stub would never fire.
      const currentAtsign = '@apkammeta';
      const enrollKey =
          'abcdef01-1a2e-43e4-93bd-378f1d366ea7.new.enrollments.__manage$currentAtsign';
      const enrollValue = '{"appName":"buzz","deviceName":"pixel",'
          '"namespace":{"buzz":"rw"},'
          '"metadata":{"keyPackage":{"opaqueToTheClient":true}}}';
      final listCommand = (EnrollVerbBuilder()
            ..operation = EnrollOperationEnum.list)
          .buildCommand();
      final secondary = MockRemoteSecondary();
      when(() => secondary.executeCommand(listCommand, auth: true))
          .thenAnswer((_) async => 'data:{"$enrollKey":$enrollValue}');

      final client = await AtClientImpl.create(
          currentAtsign,
          'buzz',
          AtClientPreference()
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit',
          remoteSecondary: secondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, AtEnrollment.create());

      final request =
          (await client.enrollmentService!.fetchEnrollmentRequests()).single;

      expect(request.metadata?['keyPackage'], isNotNull,
          reason: 'an approver reads the encapsulation target from here — the '
              'metadata is only ever written by the request that creates the '
              'record, so there is nowhere else to read it from');
      // The stub's contents are deliberately not shaped like a real key
      // package. What this asserts is pass-through of an opaque map, and a
      // stub that mimicked the envelope would read as documentation of its
      // shape — which is how this line came to describe a flat `signature`
      // field that the envelope has not had since it went to a signatures
      // list.
      expect((request.metadata!['keyPackage'] as Map)['opaqueToTheClient'],
          isTrue);
    });

    /// What an approving app passes in on the RSA path: the wrapped key it
    /// read off the enrollment notification. `AtBytes` holds base64.
    final callerSuppliedKey = base64Encode(utf8.encode('from-the-enrollee'));

    /// Drives `approve` against a pending record and returns the decision that
    /// reached at_auth.
    ///
    /// The list stub answers twice with different records: the pending one on
    /// the pre-approval read, and a metadata-less one afterwards, so
    /// conveyance short-circuits and the assertion is about the minting
    /// decision alone.
    Future<EnrollmentRequestDecision> decisionFor(
        String atSign, String pendingValue) async {
      final enrollKey =
          'abcdef01-1a2e-43e4-93bd-378f1d366ea7.new.enrollments.__manage$atSign';
      final listCommand = (EnrollVerbBuilder()
            ..operation = EnrollOperationEnum.list)
          .buildCommand();
      final secondary = MockRemoteSecondary();
      when(() => secondary.atLookUp).thenReturn(MockAtLookUp());
      var calls = 0;
      when(() => secondary.executeCommand(listCommand, auth: true))
          .thenAnswer((_) async => calls++ == 0
              ? 'data:{"$enrollKey":$pendingValue}'
              : 'data:{"$enrollKey":{"appName":"buzz","deviceName":"pixel",'
                  '"namespace":{"buzz":"rw"}}}');

      final client = await AtClientImpl.create(
          atSign,
          'buzz',
          AtClientPreference()
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit',
          remoteSecondary: secondary);
      final enrollment = RecordingAtEnrollment();
      await EnrollmentServiceImpl(client, enrollment).approve(
          EnrollmentRequestDecision.approved(
              enrollmentId: 'abcdef01-1a2e-43e4-93bd-378f1d366ea7',
              apkamSymmetricKey: AtBytes.fromString(callerSuppliedKey),
              atSign: atSign));
      return enrollment.approvals.single;
    }

    test('an enrollment that sent no wrapped key gets a minted one', () async {
      final decision = await decisionFor(
          '@apkamminted',
          '{"appName":"buzz","deviceName":"pixel",'
              '"namespace":{"buzz":"rw"},'
              '"metadata":{"keyPackage":{"opaqueToTheClient":true}}}');

      expect(decision.mintedApkamSymmetricKey, isNotNull,
          reason: 'the absent wrapped key is the whole signal that this '
              'enrollee expects the approver to mint one — it is only visible '
              'on the record the enrollee wrote, which is why the read '
              'happens before the approval');
      expect(decision.encryptedAPKAMSymmetricKey, isEmpty,
          reason: 'there is nothing to RSA-decrypt on this path');
    });

    test('an enrollment that sent a wrapped key keeps it', () async {
      final decision = await decisionFor(
          '@apkamwrapped',
          '{"appName":"buzz","deviceName":"pixel",'
              '"namespace":{"buzz":"rw"},'
              '"encryptedAPKAMSymmetricKey":"rsa-wrapped",'
              '"metadata":{"keyPackage":{"opaqueToTheClient":true}}}');

      expect(decision.mintedApkamSymmetricKey, isNull,
          reason: 'this enrollee advertised a key package for secret '
              'conveyance but generated its own symmetric key, so minting a '
              'second one would leave it unable to unwrap anything');
      expect(decision.encryptedAPKAMSymmetricKey, callerSuppliedKey,
          reason: "the caller's own decision must pass through untouched");
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
      AtClientPreference pref = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'random_namespace', pref,
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, AtEnrollment.create());
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
      AtClientPreference pref = AtClientPreference()
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient? client = await AtClientImpl.create(
          currentAtsign, 'random_namespace_1', pref,
          remoteSecondary: mockRemoteSecondary);
      client.enrollmentService =
          EnrollmentServiceImpl(client, AtEnrollment.create());
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
      AtEncryptionResult? encryptedValue = await atClient.atChops
          ?.encryptString('1234', EncryptionKeyType.aes256,
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
          'public:phone.fubar@alice',
          NotifyVerbBuilder()..useAtKeyToString = true);
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
          'public:phone.fubar@alice',
          NotifyVerbBuilder()..useAtKeyToString = true);
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
          'public:phone.unauth@alice',
          NotifyVerbBuilder()..useAtKeyToString = true);
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
