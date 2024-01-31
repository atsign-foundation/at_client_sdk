import 'dart:convert';
import 'dart:async';

import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'package:at_client/at_client.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'dart:io';

void main() {
  String namespace = 'wavi';

  void _stopSubscriptions(AtClientManager atClientManager) {
    atClientManager.atClient.notificationService.stopAllSubscriptions();
    print('subscriptions stopped');
  }

  group('Group of tests for APKAM scnearios using at_auth', () {
    test('A test to verify onboarding and initial enrollment using at_auth',
        () async {
      var atSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      var atAuth = AtAuthImpl();
      final onBoardingRequest = AtOnboardingRequest(atSign)
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..enableEnrollment = true
        ..rootDomain = 'vip.ve.atsign.zone';
      // onboard with enable enrollment set
      var atOnboardingResponse =
          await atAuth.onboard(onBoardingRequest, at_demos.cramKeyMap[atSign]!);
      print('atOnboardingResponse: $atOnboardingResponse');
      expect(atOnboardingResponse.isSuccessful, true);
      expect(atOnboardingResponse.atAuthKeys, isNotNull);
      // generate keys file
      await _generateAtKeysFile(atSign, atOnboardingResponse.enrollmentId,
          atOnboardingResponse.atAuthKeys!, 'test/testData/$atSign.atKeys');

      // auth using generated keysFile
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
        ..hiveStoragePath = 'test/hive/client';

      final atClientManager = await AtClientManager(atSign).setCurrentAtSign(
          atSign, namespace, atClientPreference,
          atChops: atAuth.atChops);
      var scanResult = await atClientManager.atClient.getKeys();
      final atClient = atClientManager.atClient;
      print(scanResult);
      // check for keys in __manage namespace
      expect(
          scanResult.contains(
              '${atOnboardingResponse.enrollmentId}.default_enc_private_key.__manage$atSign'),
          true);
      expect(
          scanResult.contains(
              '${atOnboardingResponse.enrollmentId}.default_self_enc_key.__manage$atSign'),
          true);
      expect(
          scanResult.contains(
              '${atOnboardingResponse.enrollmentId}.new.enrollments.__manage$atSign'),
          true);
      // check whether at client can create keys in different namespaces
      // #TODO change below logic to atClient.put once we have enrollment namespace checks in put method
      var putWaviKeyReponse = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:phone.wavi$atSign 1234\n');
      expect(putWaviKeyReponse, isNotEmpty);
      putWaviKeyReponse = putWaviKeyReponse!.replaceFirst('data:', '');
      expect(int.parse(putWaviKeyReponse), greaterThan(0));
      var putBuzzKeyReponse = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:email.buzz$atSign test@gmail.com\n');
      expect(putBuzzKeyReponse, isNotEmpty);
      putBuzzKeyReponse = putBuzzKeyReponse!.replaceFirst('data:', '');
      expect(int.parse(putBuzzKeyReponse), greaterThan(0));
    });
    test('A test to verify new enrollment and approval from privileged client',
        () async {
      // auth and listen to notifications from privileged client
      var atSign = ConfigUtil.getYaml()['atSign']['apkamFirstAtSign'];
      var atAuth = AtAuthImpl();
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
      await setLastReceivedNotificationDateTime(atSign, 'wavi', atClient);
      var newEnrollmentRequest = (AtNewEnrollmentRequestBuilder()
            ..setAppName('buzz')
            ..setDeviceName('iphone')
            ..setNamespaces({"buzz": "rw"})
            ..setOtp(otpResponse))
          .build();
      var atEnrollment = AtEnrollmentImpl(atSign);
      print('submitting new enrollment');
      var newAtLookup = AtLookupImpl(atSign, 'vip.ve.atsign.zone', 64);
      var newEnrollmentResponse = await atEnrollment.submitEnrollment(
          newEnrollmentRequest, newAtLookup);
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
            _stopSubscriptions(atClientManager);
          }, count: 1, max: -1));
      await completer.future;
    });

    tearDownAll(() async {
      print('tearDownAll');
    });
  });
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
  var atEnrollment = AtEnrollmentImpl(atClient.getCurrentAtSign()!);
  var enrollmentNotificationRequest = (AtEnrollmentNotificationRequestBuilder()
        ..setEncryptedApkamSymmetricKey(encryptedApkamSymmetricKey)
        ..setEnrollmentId(enrollmentId)
        ..setEnrollOperationEnum(EnrollOperationEnum.approve))
      .build();
  var approvalResponse = await atEnrollment.manageEnrollmentApproval(
      enrollmentNotificationRequest, atClient.getRemoteSecondary()!.atLookUp);
  print('approvalResponse: $approvalResponse');
  expect(approvalResponse.enrollStatus, EnrollmentStatus.approved);
}

Future<void> setLastReceivedNotificationDateTime(
    String fromAtSign, String namespace, AtClient atClient) async {
  var lastReceivedNotificationAtKey =
      AtKey.local('lastreceivednotification', fromAtSign, namespace: namespace)
          .build();
  var atNotification = AtNotification(
      '124',
      '@bob🛠:testnotificationkey',
      fromAtSign,
      '@bob🛠',
      DateTime.now().millisecondsSinceEpoch,
      MessageTypeEnum.text.toString(),
      true);

  await atClient.put(
      lastReceivedNotificationAtKey, jsonEncode(atNotification.toJson()));
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
