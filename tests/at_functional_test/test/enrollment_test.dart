import 'dart:convert';

import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
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
    aliceApkamSymmetricKey = at_demos.apkamSymmetricKeyMap[atSign]!;
    aliceDefaultEncryptionPrivateKey =
        at_demos.encryptionPrivateKeyMap[atSign]!;
    aliceSelfEncryptionKey = at_demos.aesKeyMap[atSign]!;
    alicePkamPublicKey = at_demos.pkamPublicKeyMap[atSign]!;
    await setLastReceivedNotificationDateTime();
  });

  void stopSubscriptions() {
    atClientManager.atClient.notificationService.stopAllSubscriptions();
    print('subscriptions stopped');
  }

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

    //2. send enroll request. #TODO replace below command with call to enroll method in at_client_spec once
    // https://github.com/atsign-foundation/at_client_sdk/issues/1078 is completed
    var encryptedDefaultEncPrivateKey = EncryptionUtil.encryptValue(
        aliceDefaultEncryptionPrivateKey, aliceApkamSymmetricKey);
    var encryptedSelfEncKey = EncryptionUtil.encryptValue(
        aliceSelfEncryptionKey, aliceApkamSymmetricKey);
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
    var secondApkamPublicKey = at_demos.pkamPublicKeyMap[
        '@bob🛠']; //choose any pkam public key part from @alice🛠
    var newEnrollRequest =
        'enroll:request:{"appName":"buzz","deviceName":"pixel","namespaces":{"buzz":"rw"},"otp":"$otp","apkamPublicKey":"$secondApkamPublicKey"}\n';
    var newEnrollResponse =
        await remoteSecondary_2.executeCommand(newEnrollRequest);
    print('EnrollmentResponse: $newEnrollResponse');
    expect(newEnrollResponse, isNotEmpty);

    newEnrollResponse = newEnrollResponse!.replaceFirst('data:', '');
    var enrollJson = jsonDecode(newEnrollResponse);
    var enrollmentIdFromServer = enrollJson['enrollmentId'];
    expect(enrollmentIdFromServer, isNotEmpty);
    expect(enrollJson['status'], 'pending');
    atClientManager.atClient.notificationService
        .subscribe(regex: '.new.enrollments.__manage')
        .listen(expectAsync1((enrollNotification) {
          print('got enrollment notification: $enrollNotification');
          expect(enrollNotification.key,
              '$enrollmentIdFromServer.new.enrollments.__manage');
          stopSubscriptions();
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
        at_demos.pkamPublicKeyMap['@eve🛠']; // can be any random public key
    var newEnrollRequest = TestUtils.formatCommand(
        'enroll:request:{"appName":"new_app","deviceName":"pixel","namespaces":{"new_app":"rw"},"otp":"$otp","apkamPublicKey":"$apkamPublicKey"}');
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
    Map<String, dynamic> enrollmentRequests =
        await client.fetchEnrollmentRequests();
    print(enrollmentRequests.entries);
    expect(enrollmentRequests.length, 2);

    String firstEnrollmentKey = getEnrollmentKey(
        enrollResponse1JsonDecoded['enrollmentId'], atSign);
    String secondEnrollmentKey = getEnrollmentKey(
        enrollResponse2JsonDecoded['enrollmentId'], atSign);

    expect(
        (enrollmentRequests[firstEnrollmentKey]['namespace']
            as Map<String, dynamic>)['new_app'],
        'rw');
    expect(
        (enrollmentRequests[secondEnrollmentKey]['namespace']
            as Map<String, dynamic>)['new_app'],
        'rw');
    expect(
        (enrollmentRequests[secondEnrollmentKey]['namespace']
            as Map<String, dynamic>)['wavi'],
        'r');
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
