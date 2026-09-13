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
  TestUtils.isolateStorage('enrollment_test');
  late AtClientManager atClientManager;
  late String atSign;
  String namespace = 'wavi';
  late String aliceApkamSymmetricKey;
  late String aliceDefaultEncryptionPrivateKey;
  late String aliceSelfEncryptionKey;
  String encryptedAPKAMSymmetricKey = '';

  /// A brand-new RSA-2048 keypair, for a request that must carry a key no
  /// enrollment on this atSign already holds.
  ///
  /// Every enrollment needs a keypair of its own: the atServer refuses a
  /// request installing key material that any stored record already carries,
  /// in any status. A shared demo key therefore makes the SECOND request
  /// carrying it fail, and the failure is durable server state that outlives
  /// the run that created it.
  ({String publicKey, String privateKey}) freshApkamPair() {
    final pair = RsaKeyPair.generate();
    return (
      publicKey: pair.atPublicKey.publicKey.toString(),
      privateKey: pair.atPrivateKey.privateKey.toString()
    );
  }

  setUp(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    aliceApkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
    aliceDefaultEncryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    aliceSelfEncryptionKey = aesKeyMap[atSign]!;
    encryptedAPKAMSymmetricKey = EncryptionUtil.encryptKey(
        aliceApkamSymmetricKey, encryptionPublicKeyMap[atSign]!);
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    AtClientImpl.atClientInstanceMap.clear();
    // Every client is stopped, and what comes next authenticates as a
    // different enrollment of the same atSign on the same store.
    await TestUtils.storage.allowPrincipalChange();
  });

  group('A group of tests for APKAM scenarios using at_auth', () {
    test('A test to verify onboarding and initial enrollment using at_auth',
        () async {
      var apkamAtSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      final keysIo =
          FileAtKeysIo(filePath: (atsign) => 'test/testData/$atsign.atKeys');
      // The activation is the first enrollment, and the client it hands back
      // opens on the keyfile it wrote, so the enrollment id travels with the
      // key source. This atSign was onboarded through enroll:request and so
      // has no legacy credential at all: the atServer refuses a bare `pkam:`
      // naming no enrollment.
      final atClient = await Atsign(apkamAtSign).activate(
          cramSecret: cramKeyMap[apkamAtSign]!,
          keys: keysIo,
          preference: AtClientPreference(posture: PqPosture.legacy)
            ..rootDomain = 'vip.ve.atsign.zone'
            ..rootPort = TestUtils.rootServerPort,
          namespace: namespace,
          app: 'wavi',
          device: 'pixel1',
          signingAlgo: SigningAlgoType.rsa2048,
          storage: TestUtils.storageFor(apkamAtSign));
      final onboardedKeys = await keysIo.read(apkamAtSign);
      expect(onboardedKeys.apkamSymmetricKey, isNotNull);
      final enrollmentId = atClient.enrollmentId;
      expect(enrollmentId, isNotEmpty);
      expect(atClient.connection.current.isOnline, isTrue,
          reason: 'the keyfile the activation wrote authenticates');

      var scanResult = await atClient
          .getRemoteSecondary()
          ?.executeCommand('scan\n', auth: true);

      // The enrollment record is NOT in scan, and enroll:list is where it
      // lives. `scan` filters by the connection's enrollment id, so a client
      // carrying one never sees enrollment keys however broad its grants -
      // this enrollment holds `*:rw` and `__manage:rw` and still does not.
      // Only a connection with no enrollment id at all reaches the unfiltered
      // owner view, which today means CRAM.
      final enrollmentKey =
          '$enrollmentId.new.enrollments.__manage$apkamAtSign';
      expect(scanResult?.contains(enrollmentKey), false,
          reason: 'an enrollment-scoped scan excludes enrollment keys. A true '
              'here means the connection reached the unfiltered owner view, '
              'which is what an unthreaded enrollment id used to cause');

      final ownView =
          await atClient.enrollmentService!.fetchEnrollmentRequests();
      expect(ownView.map((e) => e.enrollmentId), contains(enrollmentId),
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
      final cramEnrolmentKey = freshApkamPair();
      var enrollRequest =
          'enroll:request:{"appName":"wavi","deviceName":"pixel-${Uuid().v4().hashCode}","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"${cramEnrolmentKey.publicKey}"}\n';
      var enrollResponseFromServer = await atClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand(enrollRequest);
      expect(enrollResponseFromServer, isNotEmpty);
      enrollResponseFromServer =
          enrollResponseFromServer?.replaceFirst('data:', '');
      var enrollResponseJson = jsonDecode(enrollResponseFromServer!);
      expect(enrollResponseJson['enrollmentId'], isNotEmpty);
      expect(enrollResponseJson['status'], 'approved');

      // NOTE: a CRAM auto-approve that copies the enrolling key over
      // privatekey:at_pkam_publickey has just replaced the owner credential.
      expect(
          await atClientManager.atClient
              .getRemoteSecondary()!
              .executeCommand('update:privatekey:at_pkam_publickey '
                  '${pkamPublicKeyMap[atSign]}\n'),
          'data:-1',
          reason: 'the owner credential must be the demo keypair again before '
              'anything else authenticates as this atSign');

      // 3. Set the enrollment Id to the atClient and atLookup instance.
      atClientManager.atClient.enrollmentId =
          enrollResponseJson['enrollmentId'];
      atClientManager.atClient.getRemoteSecondary()?.atLookUp.enrollmentId =
          enrollResponseJson['enrollmentId'];
      // NOTE: the connection signs as this enrollment, so it needs that
      // enrollment's keypair, not the atSign's.
      atClientManager.atClient.getRemoteSecondary()?.atLookUp.atChops =
          AtChopsImpl(AtChopsKeys.create(
              null,
              AtPkamKeyPair.create(
                  cramEnrolmentKey.publicKey, cramEnrolmentKey.privateKey)));
      // 4. Assert that SPP is set successfully.
      var otp = (await atClientManager.atClient.getOTP()).response;

      // 5. Send the enrollment request on a connection of the test's own.
      // NOTE: the client's connection authenticates as the enrollment set in
      // step 3 as soon as its background work needs the atServer (the first
      // local write fetches that enrollment's record over it), and an
      // enroll:request arriving on an enrolled connection is judged a
      // self-enrollment rather than a new one.
      enrollRequest =
          'enroll:request:{"appName":"wavi","deviceName":"pixel-${Uuid().v4().hashCode}","namespaces":{"wavi":"rw"},"otp":"$otp","encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"${freshApkamPair().publicKey}", "encryptedAPKAMSymmetricKey":"$encryptedAPKAMSymmetricKey"}\n';
      final requestLookup =
          AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
      String? serverResponse;
      try {
        serverResponse =
            await requestLookup.executeCommand(enrollRequest, auth: false);
      } finally {
        await requestLookup.close();
      }
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
      var newAtLookup =
          AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
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
      var newAtLookup =
          AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
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
    // Fresh per request, and the two below must differ: the atServer refuses a
    // request whose key any stored enrollment already holds, so two requests
    // sharing one key make the second fail.
    String random = Uuid().v4().hashCode.toString();
    var newEnrollRequest = TestUtils.formatCommand(
        'enroll:request:{"appName":"new_app","deviceName":"pixel-6-$random","namespaces":{"new_app":"rw"},"otp":"$otp","apkamPublicKey":"${freshApkamPair().publicKey}","enrollmentStatusFilter":["pending"],"encryptedAPKAMSymmetricKey":"$encryptedAPKAMSymmetricKey"}');
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
        'enroll:request:{"appName":"new_app","deviceName":"pixel-7-$random","namespaces":{"new_app":"rw", "wavi":"r"},"otp":"$otp","apkamPublicKey":"${freshApkamPair().publicKey}","encryptedAPKAMSymmetricKey":"$encryptedAPKAMSymmetricKey"}');
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
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();
      // Every client is stopped, and what comes next authenticates as a
      // different enrollment of the same atSign on the same store.
      await TestUtils.storage.allowPrincipalChange();

      // The enrollee's own keys, completed with the two atSign-wide secrets
      // an approval releases, are what its client opens on.
      final enrolledKeys = atEnrollmentResponse.atAuthKeys!
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionPrivateKeyMap[atSign]!)
        ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!);
      final enrolledClient = await Atsign(atSign).open(
          keys: InMemoryAtKeysIo.holding(atSign, enrolledKeys),
          preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
          namespace: namespace,
          storage: TestUtils.storageForPrincipal(
              atSign, atEnrollmentResponse.enrollmentId));
      expect(enrolledClient.connection.current.isOnline, isTrue,
          reason: 'the approved enrollment authenticates');
      AtClientManager.getInstance().use(enrolledClient);

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
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();
      // Every client is stopped, and what comes next authenticates as a
      // different enrollment of the same atSign on the same store.
      await TestUtils.storage.allowPrincipalChange();

      // Get AtChops from the AtAuthKeys
      // The enrollee's keys are complete, and still refused: the atServer
      // names the denied enrollment.
      final enrolledKeys = atEnrollmentResponse.atAuthKeys!
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionPrivateKeyMap[atSign]!)
        ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!);
      await expectLater(
          () => Atsign(atSign).authenticatesAs(
              keys: InMemoryAtKeysIo.holding(atSign, enrolledKeys),
              rootDomain:
                  AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort)),
          throwsA(predicate((e) =>
              '$e'.contains('AT0025') &&
              '$e'.contains('${atEnrollmentResponse.enrollmentId} is denied'))));
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
      // read access. Written to the atServer, since the enrolled client below
      // has a store of its own and reads them from there.
      final remoteWrite = PutRequestOptions()..useRemoteAtServer = true;
      AtKey atKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();
      String value = '12345';
      AtResponse putWaviKeyResponse = await AtClientManager.getInstance()
          .atClient
          .putText(atKey, value, putRequestOptions: remoteWrite);
      expect(putWaviKeyResponse.response, isNotEmpty);

      // Put key with buzz namespace
      atKey = AtKey.self('mobile', namespace: 'buzz', sharedBy: atSign).build();
      value = '99899';
      AtResponse putBuzzKeyResponse = await AtClientManager.getInstance()
          .atClient
          .putText(atKey, value, putRequestOptions: remoteWrite);
      expect(putBuzzKeyResponse.response, isNotEmpty);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();
      // Every client is stopped, and what comes next authenticates as a
      // different enrollment of the same atSign on the same store.
      await TestUtils.storage.allowPrincipalChange();

      // The enrollee's own keys, completed with the two atSign-wide secrets
      // an approval releases, are what its client opens on; the enrolled
      // client has a store of its own, so the self key has to come with them.
      final enrolledKeys = atEnrollmentResponse.atAuthKeys!
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionPrivateKeyMap[atSign]!)
        ..defaultSelfEncryptionKey = AtBytes.fromString(aesKeyMap[atSign]!);
      final enrolledClient = await Atsign(atSign).open(
          keys: InMemoryAtKeysIo.holding(atSign, enrolledKeys),
          preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
          namespace: namespace,
          storage: TestUtils.storageForPrincipal(
              atSign, atEnrollmentResponse.enrollmentId));
      expect(enrolledClient.connection.current.isOnline, isTrue,
          reason: 'the approved enrollment authenticates');
      AtClientManager.getInstance().use(enrolledClient);

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

      // Get the key which has access to namespace. The owner's client wrote
      // it, and this client's own store has not synced it, so read it from
      // the atServer.
      AtKey getWaviKey = atKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();

      AtValue atValue = await AtClientManager.getInstance().atClient.get(
          getWaviKey,
          getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
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
      AtLookUp atLookUp =
          AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);

      AtClientManager atClientManager = await TestUtils.initAtClient(
          atSign, namespace,
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

      // Onboarding refuses to run if a keys file already exists, so clear any
      // left over from a prior run — this test mints @sachin's keys fresh
      // against the (recycled) atServer.
      final existingKeys = File(keysFilePath(cramAtSign));
      if (existingKeys.existsSync()) {
        existingKeys.deleteSync();
      }

      // (a) Initial onboarding with the CRAM secret. Mints the first
      // (manage-capable) enrollment plus the atSign's key set, writes the
      // .atKeys file, and opens the owner client on it.
      final ownerKeysIo = FileAtKeysIo(filePath: keysFilePath);
      final ownerClient = await Atsign(cramAtSign).activate(
          cramSecret: cramSecret,
          keys: ownerKeysIo,
          preference:
              TestUtils.getPreference(cramAtSign, posture: PqPosture.legacy),
          namespace: namespace,
          app: 'wavi',
          device: 'pixel-onboard',
          signingAlgo: SigningAlgoType.rsa2048,
          storage: TestUtils.storageForPrincipal(cramAtSign, 'owner'));
      expect(ownerClient.enrollmentId, isNotEmpty);
      expect(ownerClient.connection.current.isOnline, isTrue,
          reason: 'the keyfile the activation wrote authenticates');
      AtClientManager.getInstance().use(ownerClient);

      // The atSign's default encryption keypair and self-encryption key are
      // atSign-wide (shared across enrollments). Read them from the keyfile
      // the activation wrote, to hand to the enrollee for authentication
      // later.
      final ownerKeys = await ownerKeysIo.read(cramAtSign);
      final encryptionKeyPair = ownerKeys.encryptionKeyPair!;
      final selfEncryptionKey = ownerKeys.selfEncryptionKey!.key;

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
      final enrolleeLookup = AtLookupImpl(
          cramAtSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort);
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
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();
      // Every client is stopped, and what comes next authenticates as a
      // different enrollment of the same atSign on the same store.
      await TestUtils.storage.allowPrincipalChange();

      final enrolleeKeys = enrollResponse.atAuthKeys!
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionKeyPair.atPrivateKey.privateKey)
        ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey);
      final enrolleeClient = await Atsign(cramAtSign).open(
          keys: InMemoryAtKeysIo.holding(cramAtSign, enrolleeKeys),
          preference:
              TestUtils.getPreference(cramAtSign, posture: PqPosture.legacy),
          namespace: 'buzz',
          storage: TestUtils.storageForPrincipal(
              cramAtSign, enrollResponse.enrollmentId));
      expect(enrolleeClient.connection.current.isOnline, isTrue,
          reason: 'the approved enrollment authenticates');
      AtClientManager.getInstance().use(enrolleeClient);

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

/// Only ever handed to a [RemoteSecondary], which opens no local store, so
/// this carries no storage path.
AtClientPreference getClient2Preferences() {
  return AtClientPreference(posture: PqPosture.legacy)
    ..rootDomain = 'vip.ve.atsign.zone'
    ..rootPort = TestUtils.rootServerPort;
}
