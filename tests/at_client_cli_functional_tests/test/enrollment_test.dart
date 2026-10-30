import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/enrollment_operations.dart';
import 'utils/lifecycle.dart';
import 'utils/test_keys_dir.dart';

final logger = AtSignLogger('OnboardingEnrollmentTest');

/// Enrollment against a real atServer, the enrolling side through at_client's
/// `Atsign.enroll` and the approving side either hand-built on the legacy
/// wire or through `client.enrollments`.
void main() {
  AtSignLogger.root_level = 'WARNING';
  String storageDir = 'test/storage';

  String atSign1 = '@naresh🛠';
  String atSign2 = '@eggovagency🛠';
  String atSign3 = '@ashish🛠';
  String atSign4 = '@colin🛠';
  String atSign5 = '@purnima🛠';
  String atSign6 = '@srie';

  /// A client on the master keyfile [settings] names; the caller stops it.
  Future<AtClient> masterClient(
      String atSign, auth_cli.EnrollerSettings settings) async {
    final client = await openClient(atSign, settings);
    expect(client.connection.current.isOnline, true,
        reason: 'the freshly activated keys must authenticate');
    return client;
  }

  group('A group of tests to assert on authenticate functionality', () {
    test(
        'A test to verify send enroll request, approve enrollment and auth by enrollmentId',
        () async {
      // if onboard is testing use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign

      //1. Activate the atSign
      final settings_1 = settingsForAuth(atSign1);
      logger.info('activating $atSign1');
      await activateThroughCli(atSign1, settings_1);
      logger.info('successfully activated $atSign1');

      var keysFile = File(settings_1.atKeysFilePath);
      expect(keysFile.existsSync(), true);
      var keysFileJson = jsonDecode(keysFile.readAsStringSync());
      expect(keysFileJson['enrollmentId'], isNotEmpty);
      expect(keysFileJson['apkamSymmetricKey'], isNotEmpty);

      //2. authenticate first client
      logger.info('authenticating $atSign1 using onboarding keys');
      final master = await masterClient(atSign1, settings_1);
      logger.info('successfully authenticated $atSign1');
      await _setLastReceivedNotificationDateTime(master, atSign1);

      Map<String, String> namespaces = {"buzz": "rw"};
      final enrollSettings_2 = settingsForEnroll(atSign1);

      //3.1 test invalid otp
      logger.info('trying enrollment with invalid OTP');
      await expectLater(
          Atsign(atSign1).enroll(
              otp: 'a6b4df',
              app: 'buzz',
              device: 'iphone',
              namespaces: namespaces,
              keys: enrollSettings_2.keysFor(atSign1),
              preference: enrollSettings_2.preference,
              lookUps: enrollSettings_2.lookUps,
              secondaryAddressFinder: enrollSettings_2.secondaryAddressFinder),
          throwsA(predicate((dynamic e) =>
              e is AtLookUpException &&
              e.errorCode == 'AT0022' &&
              e.errorMessage
                  .contains('invalid otp. Cannot process enroll request'))));

      //3.2 a passcode from the first client
      logger.info('generating new OTP');
      final totp = (await master.enrollments.otp()).value;
      logger.info('Got new otp: $totp');

      //4.1 Start listening for notification from first client and invoke callback which approves the enrollment
      var completer = Completer<void>();

      logger
          .info('OnboardingEnrollmentTest: listening for enrollment requests');
      master.notificationService
          .subscribe(regex: '.__manage')
          .listen((notification) async {
        if (completer.isCompleted) {
          return;
        }
        logger.info('OnboardingEnrollmentTest: approving request');
        await _notificationCallback(notification, master, 'approve');
        completer.complete();
      });

      // 4.2 send enroll request for second client with valid otp
      logger.info(
          'OnboardingEnrollmentTest: sending enroll request with new OTP');
      // NOTE: `legacy` is named because this test is a test OF the legacy
      // approve wire — `_notificationCallback` hand-builds `enroll:approve`,
      // RSA-decrypting the wrapped symmetric key out of the notification and
      // re-wrapping the encryption private and self keys under it. A pq
      // request carries no wrapped key, so that code has nothing to decrypt.
      final pending = await Atsign(atSign1).enroll(
          otp: totp,
          app: 'buzz',
          device: 'iphone',
          namespaces: namespaces,
          keys: enrollSettings_2.keysFor(atSign1),
          preference: enrollSettings_2.preference,
          lookUps: enrollSettings_2.lookUps,
          secondaryAddressFinder: enrollSettings_2.secondaryAddressFinder,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);
      logger.info('enroll response ${pending.enrollmentId}');
      expect(pending.enrollmentId, isNotEmpty);

      // 4.3 Wait for the approval to happen
      logger.info('Waiting for the approval to be given');
      await completer.future;

      // 4.4 Wait for the enrolling client to successfully connect following approval
      logger.info('Waiting for the post-approval connection success');
      await pending
          .awaitApproval(retryInterval: Duration(seconds: 2))
          .timeout(Duration(seconds: 20));

      // 4.5 assert that the keys file is complete for the enrolled app
      logger.info('Verifying atKeys file');
      final enrolledClientKeysFile = File(enrollSettings_2.atKeysFilePath);
      expect(await enrolledClientKeysFile.exists(), true);
      var enrolledClientKeysFileJson =
          jsonDecode(enrolledClientKeysFile.readAsStringSync());
      expect(enrolledClientKeysFileJson['enrollmentId'], isNotEmpty);
      expect(enrolledClientKeysFileJson['apkamSymmetricKey'], isNotEmpty);

      // 4.6 Authenticate now with the approved enrollment's keys
      logger.info('Authenticating with enrollment atKeys');
      await master.stop();
      final enrolled = await openClient(atSign1, enrollSettings_2);
      expect(enrolled.connection.current.isOnline, true);
      expect(enrolled.enrollmentId, pending.enrollmentId);
      enrolledClientKeysFile.deleteSync();

      await enrolled.stop();
      logger.info('Enroll / approve / auth test completed');
    });

    test(
        'A test to verify pkam authentication is successful with the keys an activation writes',
        () async {
      // if onboard is testing use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign
      //1. Activate the atSign
      final settings_1 = settingsForAuth(atSign3);
      await activateThroughCli(atSign3, settings_1);

      //2. authenticate first client
      final client = await masterClient(atSign3, settings_1);
      await client.stop();
    });

    test(
        'A test to verify an activation succeeds when deviceName and appName are not passed',
        () async {
      // when testing activation use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign
      final settings_1 = auth_cli.EnrollerSettings(
          vePreference(
              namespace: 'wavi',
              cramSecret:
                  at_demos.cramKeyMap[atSign4] ?? atSign4.substring(1)),
          atKeysFilePath: testKeysFile(atSign4),
          storagePath: 'storage/hive/client');

      await activateThroughCli(atSign4, settings_1);
      expect(File(settings_1.atKeysFilePath).existsSync(), true);
    });

    test(
        'A test to verify send enroll request, deny enrollment and auth by enrollmentId should fail',
        () async {
      // if onboard is testing use distinct demo atsign per test,
      // since cram keys get deleted on server for already onboarded atsign
      //1. Activate the atSign
      final settings_1 = settingsForAuth(atSign5);
      await activateThroughCli(atSign5, settings_1);

      //2. authenticate first client
      final master = await masterClient(atSign5, settings_1);
      await _setLastReceivedNotificationDateTime(master, atSign5);

      //3. a passcode from the first client
      final totp = (await master.enrollments.otp()).value;
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
      master.notificationService
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
            await _notificationCallback(notification, master, 'deny');
            completer.complete();
          }, count: 1, max: -1));

      //5. enroll second client, and wait for the decision
      final enrollSettings = settingsForEnroll(atSign5);
      // Legacy named for the same reason as the approve test above: this
      // one asserts the RSA-wrapped key is present in the notification
      // and then hand-builds the deny wire, so it is about the legacy
      // shape by construction.
      final pending = await Atsign(atSign5).enroll(
          otp: totp,
          app: 'buzz',
          device: 'iphone',
          namespaces: namespaces,
          keys: enrollSettings.keysFor(atSign5),
          preference: enrollSettings.preference,
          lookUps: enrollSettings.lookUps,
          secondaryAddressFinder: enrollSettings.secondaryAddressFinder,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);
      final decided = expectLater(
          pending.awaitApproval(retryInterval: Duration(seconds: 5)),
          throwsA(predicate((dynamic e) =>
              e is AtEnrollmentException &&
              e.message == 'The enrollment: $enrollmentId is denied')));
      await completer.future;
      await decided;

      // The denial emptied the keyfile: nothing authenticates from it.
      expect(
          (await enrollSettings.keysFor(atSign5).read(atSign5))
              .holdsAuthenticationMaterial,
          false,
          reason: 'a denied enrollment leaves no credential behind');

      await master.stop();
    });

    tearDown(() async => await tearDownFunc());
  });

  group('tests to validate enrollment access control', () {
    test('validate enrollment only has access to approved namespaces',
        () async {
      // creates an enrollment with rw access to wavi namespace. Then validate
      // that updating a key with buzz namespace fails.
      String appName = 'test_app_name';
      String deviceName = 'functional_test_1';
      Map<String, String> namespaces = {'wavi': 'rw'};
      String masterKeysFilePath = testKeysFile(atSign6);
      String enrollmentAtKeysFilePath =
          testKeysFile(atSign6, suffix: 'wavi_key');

      final masterSettings = auth_cli.EnrollerSettings(
          vePreference(
              namespace: 'wavi',
              cramSecret: at_demos.cramKeyMap[atSign6] ?? atSign6.substring(1)),
          atKeysFilePath: masterKeysFilePath,
          storagePath: '$storageDir/hive/client');
      final enrollSettings = auth_cli.EnrollerSettings(
          vePreference(namespace: 'wavi'),
          atKeysFilePath: enrollmentAtKeysFilePath,
          storagePath: '$storageDir/hive/client');

      // Activate. Creates a master atKeys file at the location provided in
      // variable 'masterKeysFilePath'
      await activateThroughCli(atSign6, masterSettings);
      AtClientManager.getInstance().reset();

      // Fetch otp
      EnrollmentOperations? enrollmentOperations =
          EnrollmentOperations(atSign6);
      String? otp = await enrollmentOperations.getOtp(masterKeysFilePath);

      // Submit an enrollment request into a new keyfile at
      // 'enrollmentAtKeysFilePath', and wait for its approval in the
      // background so the wait does not starve the rest of the test.
      // NOTE: `legacy` is named because this test asserts what an approved
      // enrolment may read, not the key exchange. A pq enrolment adds a
      // post-approval round trip - the enrollee polls for the envelope holding
      // the symmetric key the approver encapsulated to its key package - which
      // on top of the 10s wait below overruns the 30s test timeout. The pq
      // enrolment path is covered by `pq_native_enroll_test.dart`.
      final pending = await Atsign(atSign6).enroll(
          otp: otp!,
          app: appName,
          device: deviceName,
          namespaces: namespaces,
          keys: enrollSettings.keysFor(atSign6),
          preference: enrollSettings.preference,
          lookUps: enrollSettings.lookUps,
          secondaryAddressFinder: enrollSettings.secondaryAddressFinder,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);
      final approved = pending.awaitApproval();
      logger.info('Sleeping for 10s');
      await Future.delayed(Duration(seconds: 10));

      // Approve the new enrollment request
      await enrollmentOperations.approve(
        atKeysFilePath: masterKeysFilePath,
        appName: appName,
        deviceName: deviceName,
      );
      await approved.whenComplete(() {
        logger.info('the enrollment wait completed');
        assert(File(enrollmentAtKeysFilePath).existsSync());
      });
      AtClientImpl.atClientInstanceMap.clear();
      enrollmentOperations = null;
      AtClientManager.getInstance().reset();

      // Authenticate using the newly created atKeys file that only has
      // access to wavi namespace
      final client = await openClient(atSign6, enrollSettings);
      expect(client.connection.current.isOnline, true);

      // Update a key with buzz namespace
      AtKey buzzKey = AtKey.public(
        'dummy_key_27',
        namespace: 'buzz',
        sharedBy: atSign6,
      ).build();
      String expectedExceptionMessage =
          'Exception: Cannot perform update on $buzzKey due to insufficient privilege';

      // The put operation is expected to fail as the new enrollment only has
      // access to wavi namespace
      await expectLater(client.put(buzzKey, 'value'), throwsA(predicate((e) {
        return e.toString() == expectedExceptionMessage;
      })));
      client.notificationService.stopAllSubscriptions();
      client.syncService.removeAllProgressListeners();
      await client.stop();
    });

    test('validate enrollment only has specified level of authorization',
        () async {
      // creates an enrollment with r access to 'delta' namespace.
      // Then validate that updating a key with buzz namespace fails.
      String appName = 'access_test_appname';
      String deviceName = 'functional_test_2';
      Map<String, String> namespaces = {'delta': 'r'};
      String masterKeysFilePath = testKeysFile(atSign2);
      String enrollmentAtKeysFilePath =
          testKeysFile(atSign2, suffix: 'wavi_key');

      final masterSettings = auth_cli.EnrollerSettings(
          vePreference(
              namespace: 'wavi',
              cramSecret: at_demos.cramKeyMap[atSign2] ?? atSign2.substring(1)),
          atKeysFilePath: masterKeysFilePath,
          storagePath: '$storageDir/hive/client');
      final enrollSettings = auth_cli.EnrollerSettings(
          vePreference(namespace: 'wavi'),
          atKeysFilePath: enrollmentAtKeysFilePath,
          storagePath: '$storageDir/hive/client');

      // Activate. Creates a master atKeys file at the location provided in
      // variable 'masterKeysFilePath'
      await activateThroughCli(atSign2, masterSettings);
      AtClientManager.getInstance().reset();

      // Fetch otp
      EnrollmentOperations enrollmentOperations = EnrollmentOperations(atSign2);
      String? otp = await enrollmentOperations.getOtp(masterKeysFilePath);

      // Submit an enrollment request into a new keyfile at
      // 'enrollmentAtKeysFilePath', and wait for its approval in the
      // background so the wait does not starve the rest of the test.
      // NOTE: `legacy` is named because this test asserts what an approved
      // enrolment may read, not the key exchange. A pq enrolment adds a
      // post-approval round trip - the enrollee polls for the envelope holding
      // the symmetric key the approver encapsulated to its key package - which
      // on top of the 10s wait below overruns the 30s test timeout. The pq
      // enrolment path is covered by `pq_native_enroll_test.dart`.
      final pending = await Atsign(atSign2).enroll(
          otp: otp!,
          app: appName,
          device: deviceName,
          namespaces: namespaces,
          keys: enrollSettings.keysFor(atSign2),
          preference: enrollSettings.preference,
          lookUps: enrollSettings.lookUps,
          secondaryAddressFinder: enrollSettings.secondaryAddressFinder,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);
      final approved = pending.awaitApproval();
      logger.info('Sleeping for 10s');
      await Future.delayed(Duration(seconds: 10));

      // Approve the new enrollment request
      await enrollmentOperations.approve(
        atKeysFilePath: masterKeysFilePath,
        appName: appName,
        deviceName: deviceName,
      );
      await approved.whenComplete(() {
        logger.info('the enrollment wait completed');
        assert(File(enrollmentAtKeysFilePath).existsSync());
      });
      AtClientImpl.atClientInstanceMap.clear();
      AtClientManager.getInstance().reset();

      // Authenticate using the newly created atKeys file that only has
      // read access to the delta namespace
      final client = await openClient(atSign2, enrollSettings);
      expect(client.connection.current.isOnline, true);

      // Update a key with delta namespace
      AtKey deltaKey = AtKey.public(
        'dummy_key_28',
        namespace: 'delta',
        sharedBy: atSign2,
      ).build();
      String expectedExceptionMessage =
          'Exception: Cannot perform update on $deltaKey due to insufficient privilege';

      // The put operation is expected to fail as the new enrollment only has
      // read access to 'delta' namespace
      await expectLater(client.put(deltaKey, 'value'), throwsA(predicate((e) {
        return e.toString() == expectedExceptionMessage;
      })));

      await client.stop();
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
  String enrollRequest;
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

/// The master keyfile [atSign]'s activation writes, and the store its
/// clients keep.
auth_cli.EnrollerSettings settingsForAuth(String atSign) {
  atSign = AtUtils.fixAtSign(atSign);
  return auth_cli.EnrollerSettings(
      vePreference(
          namespace: 'wavi',
          cramSecret: at_demos.cramKeyMap[atSign] ?? atSign.substring(1)),
      atKeysFilePath: testKeysFile(atSign),
      storagePath: 'storage/hive/client');
}

/// The keyfile a `buzz` enrollment of [atSign] is filed in, and the store
/// its clients keep.
auth_cli.EnrollerSettings settingsForEnroll(String atSign) {
  atSign = AtUtils.fixAtSign(atSign);
  return auth_cli.EnrollerSettings(vePreference(namespace: 'buzz'),
      atKeysFilePath: testKeysFile(atSign, suffix: 'buzzkey'),
      storagePath: 'storage/hive/enrolled');
}

Future<void> tearDownFunc() async {
  await evictCachedAtClients();
  bool isExists = await Directory('test/storage/').exists();
  if (isExists) {
    Directory('test/storage/').deleteSync(recursive: true);
  }
}
