import 'dart:convert';

import 'package:test/test.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'test_utils.dart';
import 'package:at_commons/at_commons.dart';

void main() {
  late AtClientManager atClientManager;
  String atSign = '@alice🛠';
  late String aliceApkamSymmetricKey;
  late String aliceDefaultEncryptionPrivateKey;
  late String aliceSelfEncryptionKey;
  late String alicePkamPublicKey;

  setUp(() async {
    var preference = TestUtils.getPreference(atSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    aliceApkamSymmetricKey = at_demos.apkamSymmetricKeyMap[atSign]!;
    aliceDefaultEncryptionPrivateKey =
        at_demos.encryptionPrivateKeyMap[atSign]!;
    aliceSelfEncryptionKey = at_demos.aesKeyMap[atSign]!;
    alicePkamPublicKey = at_demos.pkamPublicKeyMap[atSign]!;
    await AtEncryptionKeysLoader.getInstance()
        .setEncryptionKeys(atClientManager.atClient, atSign);
    setLastReceivedNotificationDateTime();
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
    var totpResponse =
        await atClient.getRemoteSecondary()!.executeCommand('totp:get\n');
    expect(totpResponse, isNotEmpty);
    String totp = totpResponse!.replaceFirst('data:', '');

    var remoteSecondary_2 = RemoteSecondary(atSign, getClient2Preferences());
    var secondApkamPublicKey = at_demos.pkamPublicKeyMap[
        '@bob🛠']; //choose any pkam public key part from @alice🛠
    var newEnrollRequest =
        'enroll:request:{"appName":"buzz","deviceName":"pixel","namespaces":{"buzz":"rw"},"totp":"$totp","apkamPublicKey":"$secondApkamPublicKey"}\n';
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
        .subscribe()
        .listen(expectAsync1((enrollNotification) {
          print('got enrollment notification: $enrollNotification');
          expect(enrollNotification.key,
              '$enrollmentIdFromServer.new.enrollments.__manage');
        }, count: 1, max: -1));
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

AtClientPreference getClient2Preferences() {
  return AtClientPreference()
    ..commitLogPath = 'test/hive/client_2/commit'
    ..hiveStoragePath = 'test/hive/client_2'
    ..isLocalStoreRequired = true
    ..rootDomain = 'vip.ve.atsign.zone';
}
