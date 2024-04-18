import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

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
    await setLastReceivedNotificationDateTime();
  });

  void stopSubscriptions(AtClientManager atClientManager) {
    atClientManager.atClient.notificationService.stopAllSubscriptions();
    print('subscriptions stopped');
  }

  group('Group of tests for APKAM scnearios using at_auth', () {
    test('A test to verify onboarding and initial enrollment using at_auth',
        () async {
      var apkamAtSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      var atAuth = atAuthBase.atAuth();
      final onBoardingRequest = AtOnboardingRequest(apkamAtSign)
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..enableEnrollment = true
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
      // check whether at client can create keys in different namespaces
      // #TODO change below logic to atClient.put once we have enrollment namespace checks in put method
      var putWaviKeyReponse = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:phone.wavi$apkamAtSign 1234\n');
      expect(putWaviKeyReponse, isNotEmpty);
      putWaviKeyReponse = putWaviKeyReponse!.replaceFirst('data:', '');
      expect(int.parse(putWaviKeyReponse), greaterThan(0));
      var putBuzzKeyReponse = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:email.buzz$apkamAtSign test@gmail.com\n');
      expect(putBuzzKeyReponse, isNotEmpty);
      putBuzzKeyReponse = putBuzzKeyReponse!.replaceFirst('data:', '');
      expect(int.parse(putBuzzKeyReponse), greaterThan(0));
    });

    test('A test to verify new enrollment and approval from privileged client',
        () async {
      // auth and listen to notifications from privileged client
      var atSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      var atAuth = atAuthBase.atAuth();
      var atAuthResponse = await atAuth.authenticate(AtAuthRequest(atSign)
        ..atKeysFilePath = 'test/testData/$atSign.atKeys'
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

      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference,
              atChops: atAuth.atChops,
              enrollmentId: atAuthResponse.enrollmentId);
      final atClient = atClientManager.atClient;
      // get otp
      var otpResponse = await atClient
          .getRemoteSecondary()!
          .executeCommand('otp:get\n', auth: true);
      expect(otpResponse, isNotEmpty);
      otpResponse = otpResponse!.replaceFirst('data:', '');
      print('otpResponse: $otpResponse');
      await setLastReceivedNotificationDateTime();
      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'buzz',
          deviceName: 'iphone',
          namespaces: {'buzz': 'rw'},
          otp: otpResponse);
      var atEnrollment = atAuthBase.atEnrollment(atSign);
      print('submitting new enrollment');
      var newAtLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
      var newEnrollmentResponse =
          await atEnrollment.submit(enrollmentRequest, newAtLookup);
      expect(newEnrollmentResponse.enrollmentId, isNotEmpty);
      expect(newEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      print('completed new enrollment request');
      var completer = Completer<void>(); // Create a Completer

      // listen for notification from privileged client and invoke callback which approves the enrollment
      atClient.notificationService
          .subscribe(regex: '.__manage')
          .listen(expectAsync1((notification) async {
            print('got enroll notification');
            await _notificationCallback(
                notification, atClientManager.atClient, 'approve');
            completer.complete();
            stopSubscriptions(atClientManager);
          }, count: 1, max: -1));
      await completer.future;
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
          'enroll:request:{"appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$alicePkamPublicKey"}\n';
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
          'enroll:request:{"appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"otp":"$spp","encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$alicePkamPublicKey"}\n';
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
      // check whether otp contains atleast one number and one alphabet
      expect(RegExp(r'^(?=.*[a-zA-Z])(?=.*\d).+$').hasMatch(otp), true);
    });
    test('A test to verify invalid OTP results in error response from server',
        () async {
      EnrollmentRequest enrollmentRequest = EnrollmentRequest(
          appName: 'buzz',
          deviceName: 'iphone',
          namespaces: {'buzz': 'rw'},
          otp: 'a1b2c3'); //random invalid OTP
      var atEnrollment = atAuthBase.atEnrollment(atSign);
      print('submitting new enrollment');
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
          deviceName: 'iphone',
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

  test('A test to verify enrollment request returns notification', () async {
    final atClient = atClientManager.atClient;
    var fromResponse =
        await atClient.getRemoteSecondary()!.executeCommand('from:$atSign\n');
    expect(fromResponse!.isNotEmpty, true);
    fromResponse = fromResponse.replaceAll('data:', '');
    //1. cram auth
    var cramDigest = TestUtils.generateCramDigest(atSign, fromResponse);
    var cramResult = await atClient
        .getRemoteSecondary()!
        .executeCommand('cram:$cramDigest\n');
    print('CRAM Result: $cramResult');

    //2. send enroll request.
    var encryptedDefaultEncPrivateKey = EncryptionUtil.encryptValue(
        aliceDefaultEncryptionPrivateKey, aliceApkamSymmetricKey);
    var encryptedSelfEncKey = EncryptionUtil.encryptValue(
        aliceSelfEncryptionKey, aliceApkamSymmetricKey);
    var atEnrollmentBase = atAuthBase.atEnrollment(atSign);
    var enrollRequest =
        'enroll:request:{"appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptedPrivateKey":"$encryptedDefaultEncPrivateKey","encryptedDefaultSelfEncryptionKey":"$encryptedSelfEncKey","apkamPublicKey":"$alicePkamPublicKey"}\n';
    var enrollResponseFromServer =
        await atClient.getRemoteSecondary()!.executeCommand(enrollRequest);
    expect(enrollResponseFromServer, isNotEmpty);
    enrollResponseFromServer =
        enrollResponseFromServer?.replaceFirst('data:', '');
    var enrollResponseJson = jsonDecode(enrollResponseFromServer!);
    expect(enrollResponseJson['enrollmentId'], isNotEmpty);
    expect(enrollResponseJson['status'], 'approved');
    // Fetch OTP
    var otpResponse =
        await atClient.getRemoteSecondary()!.executeCommand('otp:get\n');
    expect(otpResponse, isNotEmpty);
    String otp = otpResponse!.replaceFirst('data:', '');

    var remoteSecondary_2 = RemoteSecondary(atSign, getClient2Preferences());
    var secondApkamPublicKey = pkamPublicKeyMap[
        '@bob🛠']; //choose any pkam public key apart from @alice🛠. Instead of generating new key we just use a public key from demo credentials for testing
    var apkamSymmetricKey = apkamSymmetricKeyMap[atSign];
    var encryptedApkamSymmetricKey = EncryptionUtil.encryptKey(
        apkamSymmetricKey!, encryptionPublicKeyMap[atSign]!);
    var newEnrollmentRequest = EnrollmentRequest(
        appName: "buzz",
        deviceName: "pixel",
        otp: otp,
        namespaces: {"buzz": "rw"},
        apkamPublicKey: secondApkamPublicKey,
        encryptedAPKAMSymmetricKey: encryptedApkamSymmetricKey);
    var newEnrollmentResponse = await atEnrollmentBase.submit(
        newEnrollmentRequest, remoteSecondary_2.atLookUp);
    var enrollmentIdFromServer = newEnrollmentResponse.enrollmentId;
    expect(enrollmentIdFromServer, isNotEmpty);
    expect(newEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
    atClientManager.atClient.notificationService
        .subscribe(regex: '.new.enrollments.__manage')
        .listen(expectAsync1((enrollNotification) {
          print('got enrollment notification: $enrollNotification');
          expect(enrollNotification.key,
              '$enrollmentIdFromServer.new.enrollments.__manage');
          expect(enrollNotification.value, isNotNull);
          var notificationValueJson = jsonDecode(enrollNotification.value!);
          expect(notificationValueJson['appName'], 'buzz');
          expect(notificationValueJson['deviceName'], 'pixel');
          expect(notificationValueJson['namespace']['buzz'], 'rw');
          expect(
              notificationValueJson['encryptedApkamSymmetricKey'], isNotEmpty);

          stopSubscriptions(atClientManager);
        }, count: 1, max: 1));
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
    var newEnrollRequest = TestUtils.formatCommand(
        'enroll:request:{"appName":"new_app","deviceName":"pixel","namespaces":{"new_app":"rw"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey","enrollmentStatusFilter":["pending"]}');
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
        'enroll:request:{"appName":"new_app","deviceName":"pixel7","namespaces":{"new_app":"rw", "wavi":"r"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey"}');
    enrollResponse = await TestUtils.executeCommandAndParse(
        null, newEnrollRequest,
        remoteSecondary: secondRemoteSecondary);
    var enrollResponse2JsonDecoded = jsonDecode(enrollResponse!);
    expect(enrollResponse2JsonDecoded['enrollmentId'], isNotNull);
    expect(enrollResponse2JsonDecoded['status'], 'pending');

    // fetch enrollment requests through client
    List<Enrollment> enrollmentRequests =
        await client.enrollmentService.fetchEnrollmentRequests();

    expect(enrollmentRequests.length > 2, true);

    int matchCount = 0;
    for (var request in enrollmentRequests) {
      if (request.enrollmentId == enrollResponse1JsonDecoded['enrollmentId']) {
        expect(request.namespace!['new_app'], 'rw');
        expect(request.deviceName, 'pixel');
        matchCount++;
      } else if (request.enrollmentId ==
          enrollResponse2JsonDecoded['enrollmentId']) {
        expect(request.namespace!['new_app'], 'rw');
        expect(request.namespace!['wavi'], 'r');
        expect(request.deviceName, 'pixel7');
        matchCount++;
      }
    }
    // this counter is to assert that the list of requests has exactly two request matches
    expect(matchCount, 2);
  });
}

Future<void> setLastReceivedNotificationDateTime() async {
  var lastReceivedNotificationAtKey = AtKey.local('lastreceivednotification',
          AtClientManager.getInstance().atClient.getCurrentAtSign()!,
          namespace: AtClientManager.getInstance()
              .atClient
              .getPreferences()!
              .namespace)
      .build();

  var atNotification = AtNotification(
      '124',
      '@bob🛠:testnotificationkey',
      '@alice',
      '@bob🛠',
      DateTime.now().millisecondsSinceEpoch,
      MessageTypeEnum.text.toString(),
      true);

  await AtClientManager.getInstance()
      .atClient
      .put(lastReceivedNotificationAtKey, jsonEncode(atNotification.toJson()));
}

String getEnrollmentKey(String enrollmentId, String atsign) {
  return '$enrollmentId.new.enrollments.__manage$atsign';
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

Future<void> _notificationCallback(
    AtNotification notification, AtClient atClient, String response) async {
  print('enroll notification received: ${notification.toString()}');
  final notificationKey = notification.key;
  final enrollmentId =
      notificationKey.substring(0, notificationKey.indexOf('.new.enrollments'));
  var enrollParamsJson = {};
  enrollParamsJson['enrollmentId'] = enrollmentId;
  final encryptedApkamSymmetricKey =
      jsonDecode(notification.value!)['encryptedApkamSymmetricKey'];
  var atEnrollment = atAuthBase.atEnrollment(atClient.getCurrentAtSign()!);
  EnrollmentRequestDecision enrollmentRequestDecision =
      EnrollmentRequestDecision.approved(ApprovedRequestDecisionBuilder(
          enrollmentId: enrollmentId,
          encryptedAPKAMSymmetricKey: encryptedApkamSymmetricKey));
  var approvalResponse = await atEnrollment.approve(
      enrollmentRequestDecision, atClient.getRemoteSecondary()!.atLookUp);
  print('approvalResponse: $approvalResponse');
  expect(approvalResponse.enrollStatus, EnrollmentStatus.approved);
}
