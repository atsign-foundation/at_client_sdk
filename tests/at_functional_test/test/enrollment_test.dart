import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  late String atSign;
  String namespace = 'wavi';
  late String aliceApkamSymmetricKey;
  late String aliceDefaultEncryptionPrivateKey;
  late String aliceSelfEncryptionKey;
  late String alicePkamPublicKey;

  setUp(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace);
    aliceApkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
    aliceDefaultEncryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    aliceSelfEncryptionKey = aesKeyMap[atSign]!;
    alicePkamPublicKey = pkamPublicKeyMap[atSign]!;
  });

  tearDown(() {
    AtClientManager.getInstance().reset();
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('A group of tests for APKAM scenarios using at_auth', () {
    test('A test to verify onboarding and initial enrollment using at_auth',
        () async {
      var apkamAtSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      var atAuth = atAuthBase.atAuth();
      final onBoardingRequest = AtOnboardingRequest(apkamAtSign)
        ..appName = 'wavi'
        ..deviceName = 'pixel1'
        ..rootDomain = 'vip.ve.atsign.zone';
      // onboard with enable enrollment set
      var atOnboardingResponse =
          await atAuth.onboard(onBoardingRequest, cramKeyMap[apkamAtSign]!);
      print('atOnboardingResponse: $atOnboardingResponse');
      expect(atOnboardingResponse.isSuccessful, true);
      expect(atOnboardingResponse.atAuthKeys, isNotNull);
      expect(atOnboardingResponse.atAuthKeys!.apkamSymmetricKey, isNotNull);
      expect(atOnboardingResponse.enrollmentId, isNotEmpty);
      // generate keys file
      await _generateAtKeysFile(
          apkamAtSign,
          atOnboardingResponse.enrollmentId,
          atOnboardingResponse.atAuthKeys!,
          'test/testData/$apkamAtSign.atKeys');

      // auth using generated keysFile
      var atAuthResponse = await atAuth.authenticate(AtAuthRequest(apkamAtSign)
        ..atKeysFilePath = 'test/testData/$apkamAtSign.atKeys'
        ..rootDomain = 'vip.ve.atsign.zone');
      print('atAuthResponse: $atAuthResponse');
      expect(atAuthResponse.isSuccessful, true);
      expect(atAuthResponse.atAuthKeys, isNotNull);

      // create atclient instance
      var atClientPreference = AtClientPreference()
        ..rootDomain = 'vip.ve.atsign.zone'
        ..commitLogPath = 'test/hive/commit/'
        ..hiveStoragePath = 'test/hive/client'
        ..isLocalStoreRequired = true;

      final atClientManager = await AtClientManager(apkamAtSign)
          .setCurrentAtSign(apkamAtSign, namespace, atClientPreference,
              atChops: atAuth.atChops);
      //var scanResult = await atClientManager.atClient.getKeys();
      var scanResult = await atClientManager.atClient
          .getRemoteSecondary()
          ?.executeCommand('scan\n', auth: true);
      final atClient = atClientManager.atClient;
      // check for keys in __manage namespace
      expect(
          scanResult?.contains(
              '${atOnboardingResponse.enrollmentId}.default_enc_private_key.__manage$apkamAtSign'),
          true);
      expect(
          scanResult?.contains(
              '${atOnboardingResponse.enrollmentId}.default_self_enc_key.__manage$apkamAtSign'),
          true);
      expect(
          scanResult?.contains(
              '${atOnboardingResponse.enrollmentId}.new.enrollments.__manage$apkamAtSign'),
          true);
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
      expect(putBuzzKeyResponse.response, isNotEmpty);
      expect(int.parse(putBuzzKeyResponse.response), greaterThan(0));
    });
  });

  group('A group of tests for OTP and SPP', () {
    test(
        'A test to verify SPP is set and enrollment request is submitted successfully',
        () async {
      String spp = 'ABC123';
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
          'enroll:request:{"appName":"wavi","deviceName":"pixel-${Uuid().v4().hashCode}","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$alicePkamPublicKey"}\n';
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
      AtResponse atResponse = await atClientManager.atClient.setSPP(spp);
      expect(atResponse.response, 'ok');
      // 4.a Close open connection to start an unauthenticated connection.
      atClientManager.atClient.getRemoteSecondary()?.atLookUp.close();
      // 5. Send enrollment request
      enrollRequest =
          'enroll:request:{"appName":"wavi","deviceName":"pixel-${Uuid().v4().hashCode}","namespaces":{"wavi":"rw"},"otp":"$spp","encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$alicePkamPublicKey"}\n';
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
      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'buzz',
          deviceName: 'iphone-${Uuid().v4().hashCode}',
          namespaces: {'buzz': 'rw'},
          otp: 'a1b2c3'); //random invalid OTP
      var atEnrollment = atAuthBase.atEnrollment(atSign);
      var newAtLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
      expect(
          () async => atEnrollment.submit(enrollmentRequest, newAtLookup),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorCode == 'AT0011' &&
              e.errorMessage!
                  .contains('invalid otp. Cannot process enroll request'))));
    });

    test(
        'A test to verify same OTP used twice results in error response from server',
        () async {
      AtResponse atResponse = await atClientManager.atClient.getOTP();

      expect(atResponse.response.isNotEmpty, true);
      var otp = atResponse.response;
      expect(otp.length, 6);
      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'buzz',
          deviceName: 'iphone-${Uuid().v4().hashCode}',
          namespaces: {'buzz': 'rw'},
          otp: otp); //random invalid OTP
      var atEnrollment = atAuthBase.atEnrollment(atSign);
      var newAtLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
      var enrollmentResponse =
          await atEnrollment.submit(enrollmentRequest, newAtLookup);
      expect(enrollmentResponse.enrollmentId, isNotEmpty);
      expect(enrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      // submit another enrollment with same OTP
      expect(
          () async => atEnrollment.submit(enrollmentRequest, newAtLookup),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorCode == 'AT0011' &&
              e.errorMessage!
                  .contains('invalid otp. Cannot process enroll request'))));
    });
  });

  test(
      'validate client functionality to fetch pending enrollments on legacy pkam authenticated client',
      () async {
    atClientManager = await TestUtils.initAtClient(atSign, 'new_app');
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
        'enroll:request:{"appName":"new_app","deviceName":"pixel-6-$random","namespaces":{"new_app":"rw"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey","enrollmentStatusFilter":["pending"]}');
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
        'enroll:request:{"appName":"new_app","deviceName":"pixel-7-$random","namespaces":{"new_app":"rw", "wavi":"r"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey"}');
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
      atClientManager = await TestUtils.initAtClient(atSign, namespace);
      // Load encryption public key into remote secondary
      await atClientManager.atClient.getRemoteSecondary()!.executeCommand(
          'update:public:publickey${atSign} ${encryptionPublicKeyMap[atSign]}\n',
          auth: true);
      AtResponse atResponse = await atClientManager.atClient.setSPP('ABC123');
      expect(atResponse.response, 'ok');
    });

    test(
        'A test to validate client can authenticate with an approved enrollment and perform put operation',
        () async {
      // Submit an enrollment request with at_auth package
      AtEnrollmentBase atEnrollmentBase = atAuthBase.atEnrollment(atSign);
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          atSign,
          atClientManager.atClient.getPreferences()!.rootDomain,
          atClientManager.atClient.getPreferences()!.rootPort);

      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: 'ABC123',
          namespaces: {'wavi': 'rw'});
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
                  ApprovedRequestDecisionBuilder(
                      enrollmentId: atEnrollmentResponse.enrollmentId,
                      encryptedAPKAMSymmetricKey:
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
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!,
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!);
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      // Authenticate the atSign
      AtAuth atAuth = atAuthBase.atAuth(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          encryptionPrivateKeyMap[atSign]!;
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey = aesKeyMap[atSign];
      atAuthRequest.rootDomain = 'vip.ve.atsign.zone';

      AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
      expect(atAuthResponse.isSuccessful, true);

      // After authentication is successful, create an instance of atClient with enrollment Id
      // to perform put operation.
      await AtClientManager.getInstance().setCurrentAtSign(
          atSign, namespace, TestUtils.getPreference(atSign),
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
      AtEnrollmentBase atEnrollmentBase = atAuthBase.atEnrollment(atSign);
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          atSign,
          atClientManager.atClient.getPreferences()!.rootDomain,
          atClientManager.atClient.getPreferences()!.rootPort);

      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: 'ABC123',
          namespaces: {'wavi': 'rw'});
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
                  atEnrollmentResponse.enrollmentId));
      expect(approveEnrollmentResponse?.enrollStatus, EnrollmentStatus.denied);

      // Set AtClient to null and authenticate with the new auth keys generated for enrollment
      AtClientManager.getInstance().reset();
      AtClientImpl.atClientInstanceMap.clear();

      // Get AtChops from the AtAuthKeys
      AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!);
      AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!,
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!);
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      // Authenticate the atSign
      AtAuth atAuth = atAuthBase.atAuth(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          encryptionPrivateKeyMap[atSign]!;
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey = aesKeyMap[atSign];
      atAuthRequest.rootDomain = 'vip.ve.atsign.zone';

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
      AtEnrollmentBase atEnrollmentBase = atAuthBase.atEnrollment(atSign);
      int random = Uuid().v4().hashCode;
      AtLookUp atLookUp = AtLookupImpl(
          atSign,
          atClientManager.atClient.getPreferences()!.rootDomain,
          atClientManager.atClient.getPreferences()!.rootPort);

      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'wavi-$random',
          deviceName: 'iphone',
          otp: 'ABC123',
          namespaces: {'wavi': 'r'});
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
                  ApprovedRequestDecisionBuilder(
                      enrollmentId: atEnrollmentResponse.enrollmentId,
                      encryptedAPKAMSymmetricKey:
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
          atEnrollmentResponse.atAuthKeys!.apkamPublicKey!,
          atEnrollmentResponse.atAuthKeys!.apkamPrivateKey!);
      AtChopsKeys atChopsKeys =
          AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      // Authenticate the atSign
      AtAuth atAuth = atAuthBase.atAuth(atChops: atChops);
      AtAuthRequest atAuthRequest = AtAuthRequest(atSign);
      atAuthRequest.enrollmentId = atEnrollmentResponse.enrollmentId;
      atAuthRequest.atAuthKeys = atEnrollmentResponse.atAuthKeys;
      atAuthRequest.atAuthKeys?.defaultEncryptionPrivateKey =
          encryptionPrivateKeyMap[atSign]!;
      atAuthRequest.atAuthKeys?.defaultSelfEncryptionKey = aesKeyMap[atSign];
      atAuthRequest.rootDomain = 'vip.ve.atsign.zone';

      AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
      expect(atAuthResponse.isSuccessful, true);

      // After authentication is successful, create an instance of atClient with enrollment Id
      // to perform put operation.
      await AtClientManager.getInstance().setCurrentAtSign(
          atSign, namespace, TestUtils.getPreference(atSign),
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
                  'Cannot perform update on phone.wavi${atSign} due to insufficient privilege'))));

      // Get the key which does not have access to namespace and should throw an exception.
      AtKey getBuzzKey = atKey =
          AtKey.self('mobile', namespace: 'buzz', sharedBy: atSign).build();

      expect(
          () async =>
              await AtClientManager.getInstance().atClient.get(getBuzzKey),
          throwsA(predicate((dynamic e) =>
              e is AtClientException &&
              e.message.contains(
                  'Cannot perform llookup on mobile.buzz${atSign} due to insufficient privilege'))));

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
      AtEnrollmentBase atEnrollmentBase = atAuthBase.atEnrollment(atSign);
      AtLookUp atLookUp = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
      Map<String, dynamic> enrollmentMap = HashMap();
      String enrollmentIdFromServer = '';

      AtClientManager atClientManager =
          await TestUtils.initAtClient(atSign, namespace);

      AtResponse otpResponse = await atClientManager.atClient.getOTP();
      print(otpResponse.response);

      Stream<AtNotification> notificationStream = atClientManager
          .atClient.notificationService
          .subscribe(regex: "__manage");
      notificationStream.listen(expectAsync1((notification) {
        print('RCVD: $notification');
        enrollmentIdFromServer =
            notification.key.substring(0, notification.key.indexOf('.'));
        expect(notification.key, isNotEmpty);
        var enrollmentData = jsonDecode(notification.value!);
        enrollmentMap.putIfAbsent(enrollmentIdFromServer, () => enrollmentData);
      }, count: 1, max: -1));
      // Adding 5 seconds time duration for the monitor connection to start and accept the incoming notifications.
      await Future.delayed(Duration(seconds: 5));

      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'wavi',
          deviceName: 'device-$random',
          otp: otpResponse.response,
          namespaces: {'wavi': 'rw'});
      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
      print('Enrollment Response: $atEnrollmentResponse');

      // Wait until the notification is received.
      while (!enrollmentMap.containsKey(atEnrollmentResponse.enrollmentId)) {
        await Future.delayed(Duration(milliseconds: 1));
      }

      expect(atEnrollmentResponse.enrollmentId, isNotEmpty);
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(
          enrollmentMap[atEnrollmentResponse.enrollmentId]['appName'], 'wavi');
      expect(enrollmentMap[atEnrollmentResponse.enrollmentId]['deviceName'],
          'device-$random');
    });
    //To prevent failure due to latency, adding timeout for client to receive notifications sent from the server.
  }, timeout: Timeout(Duration(minutes: 1)));
}

AtClientPreference getClient2Preferences() {
  return AtClientPreference()
    ..commitLogPath = 'test/hive/client_2/commit'
    ..hiveStoragePath = 'test/hive/client_2'
    ..isLocalStoreRequired = true
    ..rootDomain = 'vip.ve.atsign.zone';
}

Future<void> _generateAtKeysFile(String atSign, String? currentEnrollmentId,
    AtAuthKeys atAuthKeys, String keysFilePath) async {
  final atKeysMap = <String, String>{
    'aesPkamPublicKey': EncryptionUtil.encryptValue(
        atAuthKeys.apkamPublicKey!, atAuthKeys.defaultSelfEncryptionKey!),
    'aesPkamPrivateKey': EncryptionUtil.encryptValue(
        atAuthKeys.apkamPrivateKey!, atAuthKeys.defaultSelfEncryptionKey!),
    'aesEncryptPublicKey': EncryptionUtil.encryptValue(
        atAuthKeys.defaultEncryptionPublicKey!,
        atAuthKeys.defaultSelfEncryptionKey!),
    'aesEncryptPrivateKey': EncryptionUtil.encryptValue(
        atAuthKeys.defaultEncryptionPrivateKey!,
        atAuthKeys.defaultSelfEncryptionKey!),
    'selfEncryptionKey': atAuthKeys.defaultSelfEncryptionKey!,
    atSign: atAuthKeys.defaultSelfEncryptionKey!,
    'apkamSymmetricKey': atAuthKeys.apkamSymmetricKey!
  };

  if (currentEnrollmentId != null) {
    atKeysMap['enrollmentId'] = currentEnrollmentId;
  }

  File atKeysFile = File(keysFilePath);

  if (!atKeysFile.existsSync()) {
    atKeysFile.createSync(recursive: true);
  }
  IOSink fileWriter = atKeysFile.openWrite();

  //generating .atKeys file at path provided in onboardingConfig
  fileWriter.write(jsonEncode(atKeysMap));
  await fileWriter.flush();
  await fileWriter.close();
}
