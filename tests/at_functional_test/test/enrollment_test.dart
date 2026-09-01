@Tags(['pq'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'sync_multiple_client_test.dart';
import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  late String atSign;
  String namespace = 'wavi';
  late String aliceApkamSymmetricKey;
  late String aliceDefaultEncryptionPrivateKey;
  late String aliceSelfEncryptionKey;
  late String aliceApkamPublicKey;
  String encryptedAPKAMSymmetricKey = '';

  setUp(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    aliceApkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
    aliceDefaultEncryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    aliceSelfEncryptionKey = aesKeyMap[atSign]!;
    // The APKAM keypair, NOT the atSign's own PKAM keypair. An enrollment
    // record whose apkamPublicKey equals the value at
    // `privatekey:at_pkam_publickey` makes an app credential and the owner
    // credential indistinguishable by value, and the atServer treats such a
    // match as proof that the flat key is a vestige of this enrollment and
    // deletes it on the enrollment's first APKAM authentication. That would
    // strip this atSign of the legacy credential the rest of the pack
    // authenticates with.
    aliceApkamPublicKey = apkamPublicKeyMap[atSign]!;
    encryptedAPKAMSymmetricKey = EncryptionUtil.encryptKey(
        aliceApkamSymmetricKey, encryptionPublicKeyMap[atSign]!);
  });

  tearDown(() {
    AtClientManager.getInstance().reset();
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('A group of tests for APKAM scenarios using at_auth', () {
    test('A test to verify onboarding and initial enrollment using at_auth',
        () async {
      var apkamAtSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      var atAuth = AtAuth.create();
      final onBoardingRequest = AtOnboardingRequest(apkamAtSign)
        ..appName = 'wavi'
        ..deviceName = 'pixel1'
        ..rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort)
        ..atKeysIo =
            FileAtKeysIo(filePath: (atsign) => 'test/testData/$atsign.atKeys');
      // onboard with enable enrollment set
      var atOnboardingResponse =
          await atAuth.onboard(onBoardingRequest, cramKeyMap[apkamAtSign]!);
      expect(atOnboardingResponse.isSuccessful, true);
      expect(atOnboardingResponse.atAuthKeys, isNotNull);
      expect(atOnboardingResponse.atAuthKeys!.apkamSymmetricKey, isNotNull);
      expect(atOnboardingResponse.enrollmentId, isNotEmpty);

      // auth using generated keysFile
      var atAuthResponse = await atAuth.authenticate(AtAuthRequest(
        apkamAtSign,
        atKeysIo:
            FileAtKeysIo(filePath: (atsign) => 'test/testData/$atsign.atKeys'),
      )..rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort));
      expect(atAuthResponse.isSuccessful, true);
      expect(atAuthResponse.atAuthKeys, isNotNull);

      // create atclient instance
      // Direct construction: no compiler names this site.
      var atClientPreference = AtClientPreference(posture: PqPosture.legacy)
        ..commitLogPath = 'test/hive/commit/'
        ..hiveStoragePath = 'test/hive/client'
        ..rootDomain = 'vip.ve.atsign.zone'
        ..rootPort = TestUtils.rootServerPort;

      // The enrollment id travels with the signer, or this client authenticates
      // over LEGACY pkam - a bare `pkam:` naming no enrollment. This atSign was
      // onboarded through enroll:request and so has no legacy credential at
      // all, and the atServer refuses that authentication by name. Passing it
      // is what `AtOnboardingServiceImpl._initAtClient` does on both of its
      // paths; this site is hand-built and had to be told.
      final atClientManager = await AtClientManager(apkamAtSign)
          .setCurrentAtSign(apkamAtSign, namespace, atClientPreference,
              atChops: atAuth.atChops,
              enrollmentId: atAuthResponse.atAuthKeys!.enrollmentId);
      //var scanResult = await atClientManager.atClient.getKeys();
      var scanResult = await atClientManager.atClient
          .getRemoteSecondary()
          ?.executeCommand('scan\n', auth: true);
      final atClient = atClientManager.atClient;

      // The enrollment record is NOT in scan, and enroll:list is where it
      // lives. `scan` filters by the connection's enrollment id, so a client
      // carrying one never sees enrollment keys however broad its grants -
      // this enrollment holds `*:rw` and `__manage:rw` and still does not.
      // Only a connection with no enrollment id at all reaches the unfiltered
      // owner view, which today means CRAM.
      //
      // This assertion used to read `contains(...), true` and passed because
      // the client was built without its enrollment id and so authenticated
      // as the owner by accident. Fixing that authentication is what exposed
      // it.
      //
      // ⚠️ The authoritative pin for the filtering rule is server-side, in
      // at_server's scan_verb_test.dart - including the discriminating case
      // that a CRAM connection DOES see these keys. This pair is the
      // CONSUMER's view of the same rule, kept here because the change is
      // visible to clients. If the two ever disagree, at_server's is the one
      // that decides.
      final enrollmentKey =
          '${atOnboardingResponse.enrollmentId}.new.enrollments.__manage$apkamAtSign';
      expect(scanResult?.contains(enrollmentKey), false,
          reason: 'an enrollment-scoped scan excludes enrollment keys. A true '
              'here means the connection reached the unfiltered owner view, '
              'which is what an untreaded enrollment id used to cause');

      final ownView =
          await atClient.enrollmentService!.fetchEnrollmentRequests();
      expect(ownView.map((e) => e.enrollmentId),
          contains(atOnboardingResponse.enrollmentId),
          reason: 'enroll:list is the management path for enrollment records, '
              'and this enrollment holds __manage:rw. Asserting it here keeps '
              'the original intent - the record was created and this client '
              'can see it - rather than dropping the check with the scan');
      // Check whether at client can create keys in different namespaces
      AtKey atKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: apkamAtSign).build();
      String value = '1234';
      AtResponse putWaviKeyResponse = await atClient.putText(atKey, value);
      expect(putWaviKeyResponse.response, isNotEmpty);

      atKey =
          AtKey.self('email', namespace: 'buzz', sharedBy: apkamAtSign).build();
      value = 'test@gmail.com';
      AtResponse putBuzzKeyResponse = await atClient.putText(atKey, value);
      // Commit-log-free: a local-first write carries no commit id (the
      // server assigns one on sync), so the response is non-empty but not
      // a positive commit number. Assert it succeeded, not a commit id.
      expect(putBuzzKeyResponse.response, isNotEmpty);
    });
  });

  group('A group of tests for OTP and SPP', () {
    test(
        'A test to verify SPP is set and enrollment request is submitted successfully',
        () async {
      var fromResponse = await atClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand('from:$atSign\n');
      expect(fromResponse!.isNotEmpty, true);
      fromResponse = fromResponse.replaceAll('data:', '');
      // 1. Cram auth
      var cramDigest = TestUtils.generateCramDigest(atSign, fromResponse);
      var cramResult = await atClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand('cram:$cramDigest\n');
      expect(cramResult, 'data:success');
      // 2. Send enroll request which will be auto approved (Because connection is CRAM Authenticated).
      var encryptedDefaultEncPrivateKey = EncryptionUtil.encryptValue(
          aliceDefaultEncryptionPrivateKey, aliceApkamSymmetricKey);
      var encryptedSelfEncKey = EncryptionUtil.encryptValue(
          aliceSelfEncryptionKey, aliceApkamSymmetricKey);
      var enrollRequest =
          'enroll:request:{"appName":"wavi","deviceName":"pixel-${Uuid().v4().hashCode}","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$aliceApkamPublicKey"}\n';
      var enrollResponseFromServer = await atClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand(enrollRequest);
      expect(enrollResponseFromServer, isNotEmpty);
      enrollResponseFromServer =
          enrollResponseFromServer?.replaceFirst('data:', '');
      var enrollResponseJson = jsonDecode(enrollResponseFromServer!);
      expect(enrollResponseJson['enrollmentId'], isNotEmpty);
      expect(enrollResponseJson['status'], 'approved');
      // 3. Set the enrollment Id to the atClient and atLookup instance.
      atClientManager.atClient.enrollmentId =
          enrollResponseJson['enrollmentId'];
      atClientManager.atClient.getRemoteSecondary()?.atLookUp.enrollmentId =
          enrollResponseJson['enrollmentId'];
      // 4. Assert that SPP is set successfully.
      var otp = (await atClientManager.atClient.getOTP()).response;

      // 4.a Close open connection to start an unauthenticated connection.
      atClientManager.atClient.getRemoteSecondary()?.atLookUp.close();
      // 5. Send enrollment request
      enrollRequest =
          'enroll:request:{"appName":"wavi","deviceName":"pixel-${Uuid().v4().hashCode}","namespaces":{"wavi":"rw"},"otp":"$otp","encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$aliceApkamPublicKey", "encryptedAPKAMSymmetricKey":"$encryptedAPKAMSymmetricKey"}\n';
      String? serverResponse = await atClientManager.atClient
          .getRemoteSecondary()
          ?.executeCommand(enrollRequest, auth: false);
      serverResponse = serverResponse?.replaceAll('data:', '');
      Map decodedServerResponse = jsonDecode(serverResponse!);
      expect(decodedServerResponse['status'], 'pending');
      expect(decodedServerResponse['enrollmentId'] != null, true);
    });

    test('A test to verify getOTP returns OTP', () async {
      AtResponse atResponse = await atClientManager.atClient.getOTP();

      expect(atResponse.response.isNotEmpty, true);
      var otp = atResponse.response;
      expect(otp.length, 6);
      expect(
          otp.contains('0') || otp.contains('o') || otp.contains('O'), false);
      // check whether otp contains at least one number and one alphabet
      expect(RegExp(r'^(?=.*[a-zA-Z])(?=.*\d).+$').hasMatch(otp), true);
    });

    test('A test to verify invalid OTP results in error response from server',
        () async {
      AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
          atSign: atSign,
          appName: 'buzz',
          deviceName: 'iphone-${Uuid().v4().hashCode}',
          namespaces: {'buzz': 'rw'},
          otp: 'a1b2c3',
          signingAlgo: SigningAlgoType.rsa2048); //random invalid OTP
      var atEnrollment = AtEnrollment.create();
      var newAtLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
      expect(
          () async => atEnrollment.submit(enrollmentRequest, newAtLookup),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorCode == 'AT0022' &&
              e.errorMessage
                  .contains('invalid otp. Cannot process enroll request'))));
    });

    test(
        'A test to verify same OTP used twice results in error response from server',
        () async {
      var otp = (await atClientManager.atClient.getOTP()).response;
      expect(otp.length, 6);
      AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
          atSign: atSign,
          appName: 'buzz',
          deviceName: 'iphone-${Uuid().v4().hashCode}',
          namespaces: {'buzz': 'rw'},
          otp: otp,
          signingAlgo: SigningAlgoType.rsa2048);
      var atEnrollment = AtEnrollment.create();
      var newAtLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
      var enrollmentResponse =
          await atEnrollment.submit(enrollmentRequest, newAtLookup);
      expect(enrollmentResponse.enrollmentId, isNotEmpty);
      expect(enrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      // submit another enrollment with same OTP
      expect(
          () async => atEnrollment.submit(enrollmentRequest, newAtLookup),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorCode == 'AT0022' &&
              e.errorMessage
                  .contains('invalid otp. Cannot process enroll request'))));
    });
  });

  test(
      'validate client functionality to fetch pending enrollments on legacy pkam authenticated client',
      () async {
    atClientManager = await TestUtils.initAtClient(atSign, 'new_app',
        posture: PqPosture.legacy);
    AtClient? client = atClientManager.atClient;
    // fetch first otp
    String? otp =
        await TestUtils.executeCommandAndParse(client, 'otp:get', auth: true);
    expect(otp, isNotNull);
    // create first enrollment request
    RemoteSecondary? secondRemoteSecondary =
        RemoteSecondary(atSign, getClient2Preferences());
    var apkamPublicKey =
        pkamPublicKeyMap['@eve🛠']; // can be any random public key
    String random = Uuid().v4().hashCode.toString();
    var newEnrollRequest = TestUtils.formatCommand(
        'enroll:request:{"appName":"new_app","deviceName":"pixel-6-$random","namespaces":{"new_app":"rw"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey","enrollmentStatusFilter":["pending"],"encryptedAPKAMSymmetricKey":"$encryptedAPKAMSymmetricKey"}');
    var enrollResponse = await TestUtils.executeCommandAndParse(
        null, newEnrollRequest,
        remoteSecondary: secondRemoteSecondary);
    Map<String, dynamic> enrollResponse1JsonDecoded =
        jsonDecode(enrollResponse!);
    expect(enrollResponse1JsonDecoded['enrollmentId'], isNotNull);
    expect(enrollResponse1JsonDecoded['status'], 'pending');

    // fetch second otp
    otp = await TestUtils.executeCommandAndParse(client, 'otp:get', auth: true);
    expect(otp, isNotNull);
    // create second enrollment request
    newEnrollRequest = TestUtils.formatCommand(
        'enroll:request:{"appName":"new_app","deviceName":"pixel-7-$random","namespaces":{"new_app":"rw", "wavi":"r"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey","encryptedAPKAMSymmetricKey":"$encryptedAPKAMSymmetricKey"}');
    enrollResponse = await TestUtils.executeCommandAndParse(
        null, newEnrollRequest,
        remoteSecondary: secondRemoteSecondary);
    var enrollResponse2JsonDecoded = jsonDecode(enrollResponse!);
    expect(enrollResponse2JsonDecoded['enrollmentId'], isNotNull);
    expect(enrollResponse2JsonDecoded['status'], 'pending');

    // fetch enrollment requests through client
    List<Enrollment> enrollmentRequests =
        await client.enrollmentService!.fetchEnrollmentRequests();

    expect(enrollmentRequests.length > 2, true);

    int matchCount = 0;
    for (var request in enrollmentRequests) {
      if (request.enrollmentId == enrollResponse1JsonDecoded['enrollmentId']) {
        expect(request.namespace!['new_app'], 'rw');
        expect(request.deviceName, 'pixel-6-$random');
        matchCount++;
      } else if (request.enrollmentId ==
          enrollResponse2JsonDecoded['enrollmentId']) {
        expect(request.namespace!['new_app'], 'rw');
        expect(request.namespace!['wavi'], 'r');
        expect(request.deviceName, 'pixel-7-$random');
        matchCount++;
      }
    }
    // this counter is to assert that the list of requests has exactly two request matches
    expect(matchCount, 2);
  });

  group(
      'A group of tests to validate approve and deny operations of an enrollment',
      () {
    setUp(() async {
      atClientManager = await TestUtils.initAtClient(atSign, namespace,
          posture: PqPosture.legacy);
      // Load encryption public key into remote secondary
      await atClientManager.atClient.getRemoteSecondary()!.executeCommand(
          'update:public:publickey$atSign ${encryptionPublicKeyMap[atSign]}\n',
          auth: true);
    });

    test(
        'A test to validate client can authenticate with an approved enrollment and perform put operation',
        () async {
      // Submit an enrollment request with at_auth package
      AtEnrollment atEnrollmentBase = AtEnrollment.create();
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          atSign,
          atClientManager.atClient.getPreferences()!.rootDomain,
          atClientManager.atClient.getPreferences()!.rootPort);

      AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
          atSign: atSign,
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: (await atClientManager.atClient.getOTP()).response,
          namespaces: {'wavi': 'rw'},
          signingAlgo: SigningAlgoType.rsa2048);
      AtEnrollmentResponse? atEnrollmentResponse =
          await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

      // Use enroll fetch to get the encryptedAPKAMSymmetricKey
      String? enrollmentFetchResponse = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()
          ?.executeCommand(
              'enroll:fetch:{"enrollmentId":"${atEnrollmentResponse.enrollmentId}"}\n',
              auth: true);
      enrollmentFetchResponse =
          enrollmentFetchResponse?.replaceAll('data:', '');
      Enrollment enrollment =
          Enrollment.fromJSON(jsonDecode(enrollmentFetchResponse!));

      // Approve enrollment
      AtEnrollmentResponse? approveEnrollmentResponse =
          await AtClientManager.getInstance()
              .atClient
              .enrollmentService
              ?.approve(EnrollmentRequestDecision.approved(
                  enrollmentId: atEnrollmentResponse.enrollmentId,
                  atSign: atSign,
                  apkamSymmetricKey: AtBytes.fromString(
                      enrollment.encryptedAPKAMSymmetricKey!)));
      expect(
          approveEnrollmentResponse?.enrollStatus, EnrollmentStatus.approved);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();

      // Get AtChops from the AtAuthKeys
      AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!);
      AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!.toString(),
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!.toString());
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      atChopsKeys.selfEncryptionKey = AESKey(aesKeyMap[atSign]!);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      // Authenticate the atSign
      AtAuth atAuth = AtAuth.create(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(
        atSign,
        atKeysIo:
            FileAtKeysIo(filePath: (atsign) => 'test/testData/$atsign.atKeys'),
      );
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey =
          AtBytes.fromString(aesKeyMap[atSign]!);
      atAuthRequest.rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);

      AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
      expect(atAuthResponse.isSuccessful, true);

      // After authentication is successful, create an instance of atClient with enrollment Id
      // to perform put operation.
      await AtClientManager.getInstance().setCurrentAtSign(
          atSign, namespace, TestUtils.getPreference(atSign,
              posture: PqPosture.legacy),
          atChops: atChops, enrollmentId: atEnrollmentResponse.enrollmentId);

      // Insert key which has access to namespace authorized by enrollment.
      AtKey atKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();
      String value = '123';
      AtResponse atResponse =
          await AtClientManager.getInstance().atClient.putText(atKey, value);
      expect(atResponse.response, isNotEmpty);

      // Insert key which DO NOT have access to namespace authorized by enrollment.
      atKey = AtKey.self('phone', namespace: 'buzz', sharedBy: atSign).build();
      expect(
          () async => await AtClientManager.getInstance()
              .atClient
              .putText(atKey, value),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message ==
                  'Cannot perform update on phone.buzz@alice🛠 due to insufficient privilege')));
    });

    test(
        'A test to validate client fails to authenticate with an denied enrollment',
        () async {
      // Submit an enrollment request with at_auth package
      AtEnrollment atEnrollmentBase = AtEnrollment.create();
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          atSign,
          atClientManager.atClient.getPreferences()!.rootDomain,
          atClientManager.atClient.getPreferences()!.rootPort);

      AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
          atSign: atSign,
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: (await atClientManager.atClient.getOTP()).response,
          namespaces: {'wavi': 'rw'},
          signingAlgo: SigningAlgoType.rsa2048);
      AtEnrollmentResponse? atEnrollmentResponse =
          await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

      // Use enroll fetch to get the encryptedAPKAMSymmetricKey
      String? enrollmentFetchResponse = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()
          ?.executeCommand(
              'enroll:fetch:{"enrollmentId":"${atEnrollmentResponse.enrollmentId}"}\n',
              auth: true);
      enrollmentFetchResponse =
          enrollmentFetchResponse?.replaceAll('data:', '');
      Enrollment.fromJSON(jsonDecode(enrollmentFetchResponse!));

      // Approve enrollment
      AtEnrollmentResponse? approveEnrollmentResponse =
          await AtClientManager.getInstance().atClient.enrollmentService?.deny(
              EnrollmentRequestDecision.denied(
                  atEnrollmentResponse.enrollmentId, currentAtSign));
      expect(approveEnrollmentResponse?.enrollStatus, EnrollmentStatus.denied);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();

      // Get AtChops from the AtAuthKeys
      AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!);
      AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!.toString(),
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!.toString());
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      // Authenticate the atSign
      AtAuth atAuth = AtAuth.create(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(
        atSign,
        atKeysIo:
            FileAtKeysIo(filePath: (atsign) => 'test/testData/$atsign.atKeys'),
      );
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey =
          AtBytes.fromString(aesKeyMap[atSign]!);
      atAuthRequest.rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);

      expect(
          () async => await atAuth.authenticate(atAuthRequest),
          throwsA(predicate((dynamic e) =>
              e is AtAuthenticationException &&
              e.message.contains(
                  'AT0025:enrollment_id: ${atAuthRequest.enrollmentId} is denied'))));
    });

    test(
        'A test to verify atclient get when enrollment request has only read access',
        () async {
      // Submit an enrollment request with at_auth package
      AtEnrollment atEnrollmentBase = AtEnrollment.create();
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          atSign,
          atClientManager.atClient.getPreferences()!.rootDomain,
          atClientManager.atClient.getPreferences()!.rootPort);

      AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
          atSign: atSign,
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: (await atClientManager.atClient.getOTP()).response,
          namespaces: {'wavi': 'r'},
          signingAlgo: SigningAlgoType.rsa2048);
      AtEnrollmentResponse? atEnrollmentResponse =
          await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

      // Use enroll fetch to get the encryptedAPKAMSymmetricKey
      String? enrollmentFetchResponse = await AtClientManager.getInstance()
          .atClient
          .getRemoteSecondary()
          ?.executeCommand(
              'enroll:fetch:{"enrollmentId":"${atEnrollmentResponse.enrollmentId}"}\n',
              auth: true);
      enrollmentFetchResponse =
          enrollmentFetchResponse?.replaceAll('data:', '');
      Enrollment enrollment =
          Enrollment.fromJSON(jsonDecode(enrollmentFetchResponse!));

      // Approve enrollment
      AtEnrollmentResponse? approveEnrollmentResponse =
          await AtClientManager.getInstance()
              .atClient
              .enrollmentService
              ?.approve(EnrollmentRequestDecision.approved(
                  enrollmentId: atEnrollmentResponse.enrollmentId,
                  atSign: atSign,
                  apkamSymmetricKey: AtBytes.fromString(
                      enrollment.encryptedAPKAMSymmetricKey!)));
      expect(
          approveEnrollmentResponse?.enrollStatus, EnrollmentStatus.approved);
      // Insert a key with wavi and buzz namespace for atClient.get to fetch the data
      // Run AtClient.get before authenticating with enrollment because enrollment has only
      // read access.
      AtKey atKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();
      String value = '12345';
      AtResponse putWaviKeyResponse =
          await AtClientManager.getInstance().atClient.putText(atKey, value);
      expect(putWaviKeyResponse.response, isNotEmpty);

      // Put key with buzz namespace
      atKey = AtKey.self('mobile', namespace: 'buzz', sharedBy: atSign).build();
      value = '99899';
      AtResponse putBuzzKeyResponse =
          await AtClientManager.getInstance().atClient.putText(atKey, value);
      expect(putBuzzKeyResponse.response, isNotEmpty);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();

      // Get AtChops from the AtAuthKeys
      AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!);
      AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!.toString(),
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!.toString());
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      // atChopsKeys.selfEncryptionKey = AESKey(aesKeyMap[atSign]!);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      // Authenticate the atSign
      AtAuth atAuth = AtAuth.create(atChops: atChops);
      AtAuthRequest atAuthRequest =
          AtAuthRequest(atSign, atKeysIo: FileAtKeysIo());
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey =
          AtBytes.fromString(aesKeyMap[atSign]!);
      atAuthRequest.rootDomain = AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);

      AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
      expect(atAuthResponse.isSuccessful, true);

      // After authentication is successful, create an instance of atClient with enrollment Id
      // to perform put operation.
      await AtClientManager.getInstance().setCurrentAtSign(
          atSign, namespace, TestUtils.getPreference(atSign,
              posture: PqPosture.legacy),
          atChops: atChops, enrollmentId: atEnrollmentResponse.enrollmentId);

      // Insert key which has access to namespace authorized by enrollment.
      // Since the enrollment has only read access, should throw an exception.
      AtKey putAtKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();

      expect(
          () async => await AtClientManager.getInstance()
              .atClient
              .putText(putAtKey, '123'),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message.contains(
                  'Cannot perform update on phone.wavi$atSign due to insufficient privilege'))));

      // Get the key which does not have access to namespace and should throw an exception.
      AtKey getBuzzKey = atKey =
          AtKey.self('mobile', namespace: 'buzz', sharedBy: atSign).build();

      expect(
          () async =>
              await AtClientManager.getInstance().atClient.get(getBuzzKey),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message.contains(
                  'Cannot perform llookup on mobile.buzz$atSign due to insufficient privilege'))));

      // Get the key which has access to namespace
      AtKey getWaviKey = atKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();

      AtValue atValue =
          await AtClientManager.getInstance().atClient.get(getWaviKey);
      expect(atValue.value, '12345');
    });
  });

  group(
      'A group of tests to verify notification requests are received via the notifications',
      () {
    test('A test to verify enrollment request is received via the notification',
        () async {
      String random = Uuid().v4().hashCode.toString();
      AtEnrollment atEnrollmentBase = AtEnrollment.create();
      AtLookUp atLookUp = AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);

      AtClientManager atClientManager =
          await TestUtils.initAtClient(atSign, namespace,
              posture: PqPosture.legacy);

      // let's initialize the notification service before we do anything else
      // to ensure that the monitor is started etc
      atClientManager.atClient.notificationService
          .subscribe(regex: 'never.never.never.never.getting.this')
          .listen((_) {});
      while ((atClientManager.atClient.notificationService
                  as NotificationServiceImpl)
              .monitor
              .currentState !=
          NotificationListenerState.listening) {
        await Future.delayed(Duration(milliseconds: 100));
      }

      Map<String, dynamic> received = {};
      Stream<AtNotification> notificationStream = atClientManager
          .atClient.notificationService
          .subscribe(regex: "__manage");
      notificationStream.listen((notification) {
        String enId =
            notification.key.substring(0, notification.key.indexOf('.'));
        var enData = jsonDecode(notification.value!);
        received[enId] = enData;
      });

      AtEnrollmentResponse atEnrollmentResponse = await atEnrollmentBase.submit(
        AtEnrollmentRequest(
            atSign: atSign,
            appName: 'wavi',
            deviceName: 'device-$random',
            otp: (await atClientManager.atClient.getOTP()).response,
            namespaces: {'wavi': 'rw'},
            signingAlgo: SigningAlgoType.rsa2048),
        atLookUp,
      );

      expect(atEnrollmentResponse.enrollmentId, isNotEmpty);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

      // Wait until the notification is received.
      // Wait until the notification is received.
      while (!received.containsKey(atEnrollmentResponse.enrollmentId)) {
        await Future.delayed(Duration(milliseconds: 10));
      }

      expect(received[atEnrollmentResponse.enrollmentId]['appName'], 'wavi');
      expect(received[atEnrollmentResponse.enrollmentId]['deviceName'],
          'device-$random');
    });
    //To prevent failure due to latency, adding timeout for client to receive notifications sent from the server.
  }, timeout: Timeout(Duration(minutes: 1)));

  group('Full enrollment round trip on a freshly CRAM-onboarded atSign', () {
    test(
        'CRAM onboard, generate OTP, enroll a second app, approve it, and '
        'verify the enrolled client can act only within its granted namespace',
        () async {
      final cramAtSign = ConfigUtil.getYaml()['atSign']['apkamSecondAtSign'];
      final cramSecret = cramKeyMap[cramAtSign]!;
      String keysFilePath(String a) => 'test/testData/$a.atKeys';
      final rootDomain =
          AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);

      // Onboarding refuses to run if a keys file already exists, so clear any
      // left over from a prior run — this test mints @sachin's keys fresh
      // against the (recycled) atServer.
      final existingKeys = File(keysFilePath(cramAtSign));
      if (existingKeys.existsSync()) {
        existingKeys.deleteSync();
      }

      // (a) Initial onboarding with the CRAM secret. Mints the first
      // (manage-capable) enrollment plus the atSign's key set, writes the
      // .atKeys file; authenticate to load those keys into AtChops.
      final ownerAuth = AtAuth.create();
      final onboardResponse = await ownerAuth.onboard(
        AtOnboardingRequest(cramAtSign)
          ..appName = 'wavi'
          ..deviceName = 'pixel-onboard'
          ..rootDomain = rootDomain
          ..atKeysIo = FileAtKeysIo(filePath: keysFilePath),
        cramSecret,
      );
      expect(onboardResponse.isSuccessful, true);
      expect(onboardResponse.enrollmentId, isNotEmpty);

      final ownerAuthResponse = await ownerAuth.authenticate(
        AtAuthRequest(cramAtSign,
            atKeysIo: FileAtKeysIo(filePath: keysFilePath))
          ..rootDomain = rootDomain,
      );
      expect(ownerAuthResponse.isSuccessful, true);

      final ownerManager = await AtClientManager.getInstance().setCurrentAtSign(
          cramAtSign, namespace, TestUtils.getPreference(cramAtSign,
              posture: PqPosture.legacy),
          atChops: ownerAuth.atChops,
          enrollmentId: onboardResponse.enrollmentId);
      final ownerClient = ownerManager.atClient;

      // The atSign's default encryption keypair and self-encryption key are
      // atSign-wide (shared across enrollments). Read them from the owner's
      // AtChops to hand to the enrollee for authentication later.
      final encryptionKeyPair =
          ownerAuth.atChops!.atChopsKeys.atEncryptionKeyPair!;
      final selfEncryptionKey =
          ownerAuth.atChops!.atChopsKeys.selfEncryptionKey!.key;

      // The enrollee fetches publickey<atSign> to wrap its apkamSymmetricKey,
      // so ensure it is published.
      await ownerClient.getRemoteSecondary()!.executeCommand(
          'update:public:publickey$cramAtSign ${encryptionKeyPair.atPublicKey.publicKey}\n',
          auth: true);

      // (b) Generate an OTP from the onboarded (manage-capable) client.
      final otp = (await ownerClient.getOTP()).response;
      expect(otp.length, 6);

      // (c) A second app submits an enrollment request with the OTP. submit
      // generates a fresh APKAM keypair and wraps its apkamSymmetricKey with
      // the atSign's default encryption public key.
      final random = Uuid().v4().hashCode;
      final enrolleeLookup =
          AtLookupImpl(cramAtSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
      final enrollResponse = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
          atSign: cramAtSign,
          appName: 'buzz-$random',
          deviceName: 'pixel-enrollee',
          otp: otp,
          namespaces: {'buzz': 'rw'},
          signingAlgo: SigningAlgoType.rsa2048,
        ),
        enrolleeLookup,
      );
      expect(enrollResponse.enrollmentId, isNotEmpty);
      expect(enrollResponse.enrollStatus, EnrollmentStatus.pending);

      // (d) The owner approves the request. enroll:fetch returns the
      // encryptedAPKAMSymmetricKey, which approve decrypts with the atSign's
      // encryption private key and re-wraps for the new enrollment.
      var fetchResponse = await ownerClient.getRemoteSecondary()!.executeCommand(
          'enroll:fetch:{"enrollmentId":"${enrollResponse.enrollmentId}"}\n',
          auth: true);
      final fetched = Enrollment.fromJSON(
          jsonDecode(fetchResponse!.replaceAll('data:', '')));
      final approveResponse = await ownerClient.enrollmentService?.approve(
          EnrollmentRequestDecision.approved(
              enrollmentId: enrollResponse.enrollmentId,
              atSign: cramAtSign,
              apkamSymmetricKey:
                  AtBytes.fromString(fetched.encryptedAPKAMSymmetricKey!)));
      expect(approveResponse?.enrollStatus, EnrollmentStatus.approved);

      // (e) Verify outcomes: the enrollee authenticates with its own APKAM
      // keypair plus the atSign's default encryption/self keys, then can act in
      // its granted namespace (buzz) but not in an ungranted one (wavi).
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();

      final enrolleeChopsKeys = AtChopsKeys.create(
          AtEncryptionKeyPair.create(encryptionKeyPair.atPublicKey.publicKey,
              encryptionKeyPair.atPrivateKey.privateKey),
          AtPkamKeyPair.create(
              enrollResponse.atAuthKeys!.apkamPublicKey!.toString(),
              enrollResponse.atAuthKeys!.apkamPrivateKey!.toString()))
        ..selfEncryptionKey = AESKey(selfEncryptionKey);
      final enrolleeChops = AtChopsImpl(enrolleeChopsKeys);

      final enrolleeAuth = AtAuth.create(atChops: enrolleeChops);
      final enrolleeAuthRequest = AtAuthRequest(cramAtSign,
          atKeysIo: FileAtKeysIo(filePath: keysFilePath))
        ..enrollmentId = enrollResponse.enrollmentId
        ..atAuthKeys = enrollResponse.atAuthKeys
        ..rootDomain = rootDomain;
      enrolleeAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionKeyPair.atPrivateKey.privateKey);
      enrolleeAuthRequest.atAuthKeys?.defaultSelfEncryptionKey =
          AtBytes.fromString(selfEncryptionKey);
      final enrolleeAuthResponse =
          await enrolleeAuth.authenticate(enrolleeAuthRequest);
      expect(enrolleeAuthResponse.isSuccessful, true);

      await AtClientManager.getInstance().setCurrentAtSign(
          cramAtSign, 'buzz', TestUtils.getPreference(cramAtSign,
              posture: PqPosture.legacy),
          atChops: enrolleeChops, enrollmentId: enrollResponse.enrollmentId);
      final enrolleeClient = AtClientManager.getInstance().atClient;

      // Granted namespace (buzz): write then read back.
      final buzzKey =
          AtKey.self('mobile', namespace: 'buzz', sharedBy: cramAtSign).build();
      final putResponse = await enrolleeClient.putText(buzzKey, '99899');
      expect(putResponse.response, isNotEmpty);
      final getValue = await enrolleeClient.get(buzzKey);
      expect(getValue.value, '99899');

      // Ungranted namespace (wavi): the server rejects the write.
      final waviKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: cramAtSign).build();
      expect(
          () async => await enrolleeClient.putText(waviKey, '123'),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message.contains('insufficient privilege'))));
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}

AtClientPreference getClient2Preferences() {
  // Direct construction: no compiler names this site.
  return AtClientPreference(posture: PqPosture.legacy)
    ..commitLogPath = 'test/hive/client_2/commit'
    ..hiveStoragePath = 'test/hive/client_2'
    ..rootDomain = 'vip.ve.atsign.zone'
    ..rootPort = TestUtils.rootServerPort;
}
