import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/enrollment_operations.dart';

var pkamPublicKey;
var pkamPrivateKey;
var encryptionPublicKey;
var encryptionPrivateKey;
var selfEncryptionKey;

final logger = AtSignLogger('OnboardingEnrollmentTest');

void main() {
  AtSignLogger.root_level = 'WARNING';
  String storageDir = 'test/storage';

  String atSign1 = '@naresh🛠';
  String atSign2 = '@eggovagency🛠';
  String atSign3 = '@ashish🛠';
  String atSign4 = '@colin🛠';
  String atSign5 = '@purnima🛠';
  String atSign6 = '@srie';
  // String atSign1 = '@cli_test_01';
  // String atSign2 = '@cli_test_02';
  // String atSign3 = '@cli_test_03';
  // String atSign4 = '@cli_test_04';
  // String atSign5 = '@cli_test_05';
  // String atSign6 = '@cli_test_06';

  group('A group of tests to assert on authenticate functionality', () {
    test(
        'A test to verify send enroll request, approve enrollment and auth by enrollmentId',
        () async {
      // if onboard is testing use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign

      //1. Onboard first client
      AtOnboardingPreference preference_1 = getPreferenceForAuth(atSign1);
      AtOnboardingService? onboardingService_1 =
          AtOnboardingServiceImpl(atSign1, preference_1);

      logger.info('onboarding $atSign1');
      bool status = await onboardingService_1.onboard();
      expect(status, true);
      logger.info('successfully onboarded $atSign1');

      preference_1.privateKey = pkamPrivateKey;
      var keysFilePath = preference_1.atKeysFilePath;
      var keysFile = File(keysFilePath!);
      expect(keysFile.existsSync(), true);
      var keysFileContent = keysFile.readAsStringSync();
      var keysFileJson = jsonDecode(keysFileContent);
      expect(keysFileJson['enrollmentId'], isNotEmpty);
      expect(keysFileJson['apkamSymmetricKey'], isNotEmpty);

      //2. authenticate first client
      logger.info('authenticating $atSign1 using onboarding keys');
      var authResult = await onboardingService_1.authenticate();
      expect(authResult, true);
      logger.info('successfully authenticated $atSign1');
      await _setLastReceivedNotificationDateTime(
          onboardingService_1.atClient!, atSign1);

      Map<String, String> namespaces = {"buzz": "rw"};
      //3.1 test invalid otp
      String totp = 'a6b4df';
      AtOnboardingPreference enrollPreference_2 =
          getPreferenceForEnroll(atSign1);
      AtOnboardingService? onboardingService_2 =
          AtOnboardingServiceImpl(atSign1, enrollPreference_2);

      logger.info('trying enrollment with invalid OTP');
      await expectLater(
          onboardingService_2.enroll('buzz', 'iphone', totp, namespaces),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorCode == 'AT0022' &&
              e.errorMessage
                  .contains('invalid otp. Cannot process enroll request'))));

      //3.2 run otp:get from first client
      logger.info('generating new OTP');
      totp = (await onboardingService_1.atClient!
          .getRemoteSecondary()!
          .executeCommand('otp:get\n', auth: true))!;
      totp = totp.replaceFirst(RegExp(r'^data:'), '');
      totp = totp.trim();
      logger.info('Got new otp: $totp');

      //4.1 Start listening for notification from first client and invoke callback which approves the enrollment
      var completer = Completer<void>();

      logger
          .info('OnboardingEnrollmentTest: listening for enrollment requests');
      onboardingService_1.atClient!.notificationService
          .subscribe(regex: '.__manage')
          .listen((notification) async {
        if (completer.isCompleted) {
          return;
        }
        logger.info('OnboardingEnrollmentTest: approving request');
        await _notificationCallback(
            notification, onboardingService_1!.atClient!, 'approve');
        completer.complete();
      });

      // 4.2 send enroll request for second client with valid otp
      logger.info(
          'OnboardingEnrollmentTest: sending enroll request with new OTP');
      var enrollResponse = await onboardingService_2.sendEnrollRequest(
          'buzz', 'iphone', totp, namespaces);
      logger.info('enroll response $enrollResponse');
      // enrollment id from the response
      var enrollmentId = enrollResponse.enrollmentId;
      expect(enrollmentId, isNotEmpty);
      expect(enrollResponse.enrollStatus, EnrollmentStatus.pending);

      // 4.3 Wait for the approval to happen
      logger.info('Waiting for the approval to be given');
      await completer.future;

      // 4.4 Wait for the enrolling client to successfully connect following approval
      logger.info('Waiting for the post-approval connection success');
      await onboardingService_2
          .awaitApproval(enrollResponse, retryInterval: Duration(seconds: 2))
          .timeout(Duration(seconds: 20));

      // 4.5 Wait for the enrolling client to generate its keys file
      logger.info('Creating atKeys file');
      await onboardingService_2.createAtKeysFile(enrollResponse);

      // 4.6 assert that the keys file is created for enrolled app
      logger.info('Verifying atKeys file');
      final enrolledClientKeysFile = File(enrollPreference_2.atKeysFilePath!);
      while (!await enrolledClientKeysFile.exists()) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      expect(await enrolledClientKeysFile.exists(), true);
      var enrolledClientKeysFileContent =
          enrolledClientKeysFile.readAsStringSync();
      var enrolledClientKeysFileJson =
          jsonDecode(enrolledClientKeysFileContent);
      expect(enrolledClientKeysFileJson['enrollmentId'], isNotEmpty);
      expect(enrolledClientKeysFileJson['apkamSymmetricKey'], isNotEmpty);

      // 4.7 Authenticate now with the approved enrollmentID
      logger.info('Authenticating with enrollment atKeys');
      bool authResultWithEnrollment =
          await onboardingService_2.authenticate(enrollmentId: enrollmentId);
      expect(authResultWithEnrollment, true);
      enrolledClientKeysFile.deleteSync();

      await onboardingService_1.close();
      await onboardingService_2.close();
      onboardingService_1 = onboardingService_2 = null;
      logger.info('Enroll / approve / auth test completed');
    });

    test(
        'A test to verify pkam authentication is successful when enableEnrollmentDuringOnboard flag is set to false',
        () async {
      // if onboard is testing use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign
      //1. Onboard first client
      AtOnboardingPreference preference_1 = getPreferenceForAuth(atSign3);
      AtOnboardingService? onboardingService_1 =
          AtOnboardingServiceImpl(atSign3, preference_1);
      bool status = await onboardingService_1.onboard();
      expect(status, true);
      preference_1.privateKey = pkamPrivateKey;

      //2. authenticate first client
      var authStatus = await onboardingService_1.authenticate();
      expect(authStatus, true);

      await onboardingService_1.close();
      onboardingService_1 = null;
    });

    test(
        'A test to verify an onboarding exception is NOT thrown when enableEnrollmentDuringOnboard is set to true and deviceName and appName are not passed',
        () async {
      // when testing onboard() use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign
      // preference without appName and deviceName
      AtOnboardingPreference preference_1 = AtOnboardingPreference()
        ..rootDomain = 'vip.ve.atsign.zone'
        ..isLocalStoreRequired = true
        ..hiveStoragePath = 'storage/hive/client'
        ..commitLogPath = 'storage/hive/client/commit'
        ..cramSecret = at_demos.cramKeyMap[atSign4] ?? atSign4.substring(1)
        ..namespace =
            'wavi' // unique identifier that can be used to identify data from your app
        ..rootDomain = 'vip.ve.atsign.zone';

      AtOnboardingService? onboardingService_1 =
          AtOnboardingServiceImpl(atSign4, preference_1);
      bool onboardStatus = await onboardingService_1.onboard();
      expect(onboardStatus, true);

      await onboardingService_1.close();
      onboardingService_1 = null;
    });

    test(
        'A test to verify send enroll request, deny enrollment and auth by enrollmentId should fail',
        () async {
      // if onboard is testing use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign
      //1. Onboard first client
      AtOnboardingPreference preference_1 = getPreferenceForAuth(atSign5);
      AtOnboardingService? onboardingService_1 =
          AtOnboardingServiceImpl(atSign5, preference_1);
      bool status = await onboardingService_1.onboard();
      expect(status, true);
      preference_1.privateKey = pkamPrivateKey;

      //2. authenticate first client
      await onboardingService_1.authenticate();
      await _setLastReceivedNotificationDateTime(
          onboardingService_1.atClient!, atSign5);

      //3. run otp:get from first client
      String? totp = await onboardingService_1.atClient!
          .getRemoteSecondary()!
          .executeCommand('otp:get\n', auth: true);
      totp = totp!.replaceFirst(RegExp(r'^data:'), '');
      totp = totp.trim();
      logger.finer('otp: $totp');
      Map<String, String> namespaces = {"buzz": "rw"};
      expect(totp.length, 6);
      expect(totp.contains('0') || totp.contains('o') || totp.contains('O'),
          false);
      // check whether otp contains at least one number and one alphabet
      expect(RegExp(r'^(?=.*[a-zA-Z])(?=.*\d).+$').hasMatch(totp), true);

      var completer = Completer<void>(); // Create a Completer

      //4. Subscribe to enrollment notifications; we will deny it when it arrives
      String enrollmentId = '';
      onboardingService_1.atClient!.notificationService
          .subscribe(regex: '.__manage')
          .listen(expectAsync1((notification) async {
            logger.finer('got enroll notification');
            final notificationKey = notification.key;
            enrollmentId = notificationKey.substring(
                0, notificationKey.indexOf('.new.enrollments'));
            expect(notification.value, isNotNull);
            var notificationValueJson = jsonDecode(notification.value!);
            expect(notificationValueJson['encryptedApkamSymmetricKey'],
                isNotEmpty);
            expect(notificationValueJson['appName'], 'buzz');
            expect(notificationValueJson['deviceName'], 'iphone');
            expect(notificationValueJson['namespace']['buzz'], 'rw');
            await _notificationCallback(
                notification, onboardingService_1!.atClient!, 'deny');
            completer.complete();
          }, count: 1, max: -1));

      //5. enroll second client
      preference_1 = getPreferenceForEnroll(atSign5);
      AtOnboardingServiceImpl? onboardingService_2 =
          AtOnboardingServiceImpl(atSign5, preference_1);

      expectLater(
          onboardingService_2.enroll(
            'buzz',
            'iphone',
            totp,
            namespaces,
            retryInterval: Duration(seconds: 5),
          ),
          throwsA(predicate((dynamic e) =>
              e is AtEnrollmentException &&
              e.message == 'The enrollment: $enrollmentId is denied')));
      await completer.future;

      await onboardingService_1.close();
      await onboardingService_2.close();
      onboardingService_1 = onboardingService_2 = null;
    });

    tearDown(() async => await tearDownFunc());
  });

  group('tests to validate enrollment access control', () {
		setUp(() async {
			await Directory('$storageDir/keys/').create(recursive: true);
		});

    test('validate enrollment only has access to approved namespaces',
        () async {
      // creates an enrollment with rw access to wavi namespace. Then validate
      // that updating a key with buzz namespace fails.
      String appName = 'test_app_name';
      String deviceName = 'functional_test_1';
      Map<String, String> namespaces = {'wavi': 'rw'};
      String masterKeysFilePath = '$storageDir/keys/${atSign6}_key.atKeys';
      String enrollmentAtKeysFilePath =
          '$storageDir/keys/${atSign6}_wavi_key.atKeys';

      AtOnboardingPreference preference = AtOnboardingPreference()
        ..rootDomain = 'vip.ve.atsign.zone'
        ..isLocalStoreRequired = true
        ..hiveStoragePath = '$storageDir/hive/client'
        ..commitLogPath = '$storageDir/hive/client/commit'
        ..namespace =
            'wavi' // Unique identifier that can be used to identify data from your app
        ..rootDomain = 'vip.ve.atsign.zone';

      // Init an OnboardingService instance and onboard. Creates a master
      // atKeys file at the location provided in variable 'masterKeysFilePath'
      AtOnboardingService? onboardingService = AtOnboardingServiceImpl(
        atSign6,
        preference
          ..cramSecret = at_demos.cramKeyMap[atSign6] ?? atSign6.substring(1)
          ..atKeysFilePath = masterKeysFilePath,
      );
      await onboardingService.onboard();
      await onboardingService.close();
      onboardingService = null;
      AtClientManager.getInstance().reset();

      // Fetch otp
      EnrollmentOperations? enrollmentOperations = EnrollmentOperations(atSign6);
      String? otp = await enrollmentOperations.getOtp(masterKeysFilePath);

      // Create a new instance of OnboardingService that will be used to send an
      // enrollment request. Once this request is approved, this creates a new
      // atKeys file at the location provided in 'enrollmentAtKeysFilePath'
      onboardingService = AtOnboardingServiceImpl(
        atSign6,
        preference..atKeysFilePath = enrollmentAtKeysFilePath,
      );

      // Await has NOT been added below to ensure that the onboardingService.enroll()
      // method call does not starve the rest of the test; but still will be
      // waiting for enrollment approval in the background
      Future<AtEnrollmentResponse> enrollRequestResponse =
          onboardingService.enroll(
        appName,
        deviceName,
        otp!,
        namespaces,
      );
      logger.info('Sleeping for 10s');
      await Future.delayed(Duration(seconds: 10));

      // Approve the new enrollment request
      AtEnrollmentResponse? enrollApproveResponse =
          await enrollmentOperations.approve(
        atKeysFilePath: masterKeysFilePath,
        appName: appName,
        deviceName: deviceName,
      );
      await enrollRequestResponse.whenComplete(() {
        logger.info('OnboardingService.enroll() completed execution');
        assert(File(enrollmentAtKeysFilePath).existsSync());
      });
      AtClientImpl.atClientInstanceMap.clear();
      await onboardingService.close();
      onboardingService = null;
      enrollmentOperations = null;
      AtClientManager.getInstance().reset();

      // Create a new instance of OnboardingCli and authenticate using the newly
      // created atKeys file that only has access to wavi namespace
      onboardingService = AtOnboardingServiceImpl(
        atSign6,
        preference..atKeysFilePath = enrollmentAtKeysFilePath,
      );
      bool authStatus = await onboardingService.authenticate(
        enrollmentId: enrollApproveResponse.enrollmentId,
      );
      expect(authStatus, true);

      // Fetch the atClient instance in OnboardingCli. Then update a key with
      // buzz namespace
      AtClient? client = onboardingService.atClient;
      AtKey buzzKey = AtKey.public(
        'dummy_key_27',
        namespace: 'buzz',
        sharedBy: atSign6,
      ).build();
      String expectedExceptionMessage =
          'Exception: Cannot perform update on $buzzKey due to insufficient privilege';

      // The put operation is expected to fail as the new enrollment only has
      // access to wavi namespace
      await expectLater(client?.put(buzzKey, 'value'), throwsA(predicate((e) {
        return e.toString() == expectedExceptionMessage;
      })));
      onboardingService.atClient?.notificationService.stopAllSubscriptions();
      onboardingService.atClient?.syncService.removeAllProgressListeners();
      await onboardingService.close();
      onboardingService = null;
    });

    test('validate enrollment only has specified level of authorization',
        () async {
      // creates an enrollment with r access to 'delta' namespace.
      // Then validate that updating a key with buzz namespace fails.
      String appName = 'access_test_appname';
      String deviceName = 'functional_test_2';
      Map<String, String> namespaces = {'delta': 'r'};
      String masterKeysFilePath = '$storageDir/keys/${atSign2}_key.atKeys';
      String enrollmentAtKeysFilePath =
          '$storageDir/keys/${atSign2}_wavi_key.atKeys';

      AtOnboardingPreference preference = AtOnboardingPreference()
        ..rootDomain = 'vip.ve.atsign.zone'
        ..isLocalStoreRequired = true
        ..hiveStoragePath = '$storageDir/hive/client'
        ..commitLogPath = '$storageDir/hive/client/commit'
        ..namespace =
            'wavi' // Unique identifier that can be used to identify data from your app
        ..rootDomain = 'vip.ve.atsign.zone';

      // Init an OnboardingService instance and onboard. Creates a master
      // atKeys file at the location provided in variable 'masterKeysFilePath'
      AtOnboardingService? onboardingService = AtOnboardingServiceImpl(
        atSign2,
        preference
          ..cramSecret = at_demos.cramKeyMap[atSign2] ?? atSign2.substring(1)
          ..atKeysFilePath = masterKeysFilePath,
      );
      await onboardingService.onboard();
      await onboardingService.close();
      onboardingService = null;
      AtClientManager.getInstance().reset();

      // Fetch otp
      EnrollmentOperations enrollmentOperations = EnrollmentOperations(atSign2);
      String? otp = await enrollmentOperations.getOtp(masterKeysFilePath);

      // Create a new instance of OnboardingService that will be used to send an
      // enrollment request. Once this request is approved, this creates a new
      // atKeys file at the location provided in 'enrollmentAtKeysFilePath'
      onboardingService = AtOnboardingServiceImpl(
        atSign2,
        preference..atKeysFilePath = enrollmentAtKeysFilePath,
      );

      // Await has NOT been added below to ensure that the onboardingService.enroll()
      // method call does not starve the rest of the test; but still will be
      // waiting for enrollment approval in the background
      Future<AtEnrollmentResponse> enrollRequestResponse =
          onboardingService.enroll(
        appName,
        deviceName,
        otp!,
        namespaces,
      );
      logger.info('Sleeping for 10s');
      await Future.delayed(Duration(seconds: 10));

      // Approve the new enrollment request
      AtEnrollmentResponse? enrollApproveResponse =
          await enrollmentOperations.approve(
        atKeysFilePath: masterKeysFilePath,
        appName: appName,
        deviceName: deviceName,
      );
      await enrollRequestResponse.whenComplete(() {
        logger.info('OnboardingService.enroll() completed execution');
        assert(File(enrollmentAtKeysFilePath).existsSync());
      });
      AtClientImpl.atClientInstanceMap.clear();
      await onboardingService.close();
      onboardingService = null;
      AtClientManager.getInstance().reset();

      // Create a new instance of OnboardingCli and authenticate using the newly
      // created atKeys file that only has access to wavi namespace
      onboardingService = AtOnboardingServiceImpl(
        atSign2,
        preference..atKeysFilePath = enrollmentAtKeysFilePath,
      );
      bool authStatus = await onboardingService.authenticate(
        enrollmentId: enrollApproveResponse.enrollmentId,
      );
      expect(authStatus, true);

      // Fetch the atClient instance in OnboardingCli. Then update a key with
      // buzz namespace
      AtClient? client = onboardingService.atClient;
      AtKey deltaKey = AtKey.public(
        'dummy_key_28',
        namespace: 'delta',
        sharedBy: atSign2,
      ).build();
      String expectedExceptionMessage =
          'Exception: Cannot perform update on $deltaKey due to insufficient privilege';

      // The put operation is expected to fail as the new enrollment only has
      // read access to 'delta' namespace
      await expectLater(client?.put(deltaKey, 'value'), throwsA(predicate((e) {
        return e.toString() == expectedExceptionMessage;
      })));

      await onboardingService.close();
    });

    tearDown(() async {
      await tearDownFunc();
    });
  });
}

Future<void> _notificationCallback(
    AtNotification notification, AtClient atClient, String response) async {
  logger.info('enroll notification received: ${notification.toString()}');
  final notificationKey = notification.key;
  final enrollmentId =
      notificationKey.substring(0, notificationKey.indexOf('.new.enrollments'));
  var enrollRequest;
  var enrollParamsJson = {};
  enrollParamsJson['enrollmentId'] = enrollmentId;
  final encryptedApkamSymmetricKey =
      jsonDecode(notification.value!)['encryptedApkamSymmetricKey'];
  var encryptionPrivateKey =
      await atClient.getLocalSecondary()!.getEncryptionPrivateKey();
  var selfEncryptionKey =
      await atClient.getLocalSecondary()!.getEncryptionSelfKey();
  // ignore: deprecated_member_use
  final apkamSymmetricKey = EncryptionUtil.decryptKey(
      encryptedApkamSymmetricKey, encryptionPrivateKey!);
  var encryptedDefaultPrivateEncKey =
      EncryptionUtil.encryptValue(encryptionPrivateKey, apkamSymmetricKey);
  var encryptedDefaultSelfEncKey =
      EncryptionUtil.encryptValue(selfEncryptionKey!, apkamSymmetricKey);
  enrollParamsJson['encryptedDefaultEncryptionPrivateKey'] =
      encryptedDefaultPrivateEncKey;
  enrollParamsJson['encryptedDefaultSelfEncryptionKey'] =
      encryptedDefaultSelfEncKey;
  if (response == 'approve') {
    enrollRequest = 'enroll:approve:${jsonEncode(enrollParamsJson)}\n';
    logger.info('enroll approval request to server: $enrollRequest');
  } else {
    enrollRequest = 'enroll:deny:${jsonEncode(enrollParamsJson)}\n';
    logger.info('enroll denial request $enrollRequest');
  }
  String? enrollResponse = await atClient
      .getRemoteSecondary()!
      .executeCommand(enrollRequest, auth: true);
  logger.info('enroll Response from server: $enrollResponse');
  expect(enrollResponse, isNotEmpty);
  enrollResponse = enrollResponse!.replaceFirst(RegExp(r'^data:'), '');
  var enrollResponseJson = jsonDecode(enrollResponse);
  if (response == 'approve') {
    expect(enrollResponseJson['status'], 'approved');
  } else {
    expect(enrollResponseJson['status'], 'denied');
  }
  expect(enrollResponseJson['enrollmentId'], enrollmentId);
}

Future<void> _setLastReceivedNotificationDateTime(
    AtClient atClient, String atSign) async {
  var lastReceivedNotificationAtKey = AtKey.local(
          'lastreceivednotification', atClient.getCurrentAtSign()!,
          namespace: atClient.getPreferences()!.namespace)
      .build();

  var atNotification = AtNotification(
      '124',
      '@bob🛠:testnotificationkey',
      atSign,
      '@bob🛠',
      DateTime.now().millisecondsSinceEpoch,
      MessageTypeEnum.key.toString(),
      true);

  await atClient.put(
      lastReceivedNotificationAtKey, jsonEncode(atNotification.toJson()));
}

AtOnboardingPreference getPreferenceForAuth(String atSign) {
  atSign = AtUtils.fixAtSign(atSign);
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..rootDomain = 'vip.ve.atsign.zone'
    ..isLocalStoreRequired = true
    ..hiveStoragePath = 'storage/hive/client'
    ..commitLogPath = 'storage/hive/client/commit'
    ..cramSecret = at_demos.cramKeyMap[atSign] ?? atSign.substring(1)
    ..namespace =
        'wavi' // unique identifier that can be used to identify data from your app
    ..atKeysFilePath =
        'test/storage/.atsign/keys/${atSign}_key.atKeys'
    ..appName = 'wavi'
    ..deviceName = 'pixel'
    ..rootDomain = 'vip.ve.atsign.zone';

  return atOnboardingPreference;
}

AtOnboardingPreference getPreferenceForEnroll(String atSign) {
  atSign = AtUtils.fixAtSign(atSign);
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace =
        'buzz' // unique identifier that can be used to identify data from your app
    ..atKeysFilePath =
        '${Platform.environment['HOME']}/.atsign/keys/${atSign}_buzzkey.atKeys'
    ..appName = 'buzz'
    ..deviceName = 'iphone'
    ..rootDomain = 'vip.ve.atsign.zone';
  return atOnboardingPreference;
}

Future<void> getAtKeys(String atSign) async {
  AtOnboardingPreference preference = getPreferenceForAuth(atSign);
  String? filePath = preference.atKeysFilePath;
  var fileContents = File(filePath!).readAsStringSync();
  var keysJSON = json.decode(fileContents);
  selfEncryptionKey = keysJSON['selfEncryptionKey'];

  pkamPublicKey = EncryptionUtil.decryptValue(
      keysJSON['aesPkamPublicKey'], selfEncryptionKey);
  pkamPrivateKey = EncryptionUtil.decryptValue(
      keysJSON['aesPkamPrivateKey'], selfEncryptionKey);
  encryptionPublicKey = EncryptionUtil.decryptValue(
      keysJSON['aesEncryptPublicKey'], selfEncryptionKey);
  encryptionPrivateKey = EncryptionUtil.decryptValue(
      keysJSON['aesEncryptPrivateKey'], selfEncryptionKey);
}

Future<void> tearDownFunc() async {
  AtClientManager.getInstance().reset();
  bool isExists = await Directory('test/storage/').exists();
  if (isExists) {
    Directory('test/storage/').deleteSync(recursive: true);
  }
}
