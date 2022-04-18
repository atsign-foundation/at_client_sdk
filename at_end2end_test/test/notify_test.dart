import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'test_utils.dart';

void main() {
  var currentAtSign, sharedWithAtSign;
  AtClientManager? currentAtSignClientManager, sharedWithAtSignClientManager;
  var namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    // Create atClient instance for currentAtSign
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // Set Encryption Keys for currentAtSign
    await TestUtils.setEncryptionKeys(currentAtSign);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    // Create atClient instance for atSign2
    sharedWithAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestUtils.getPreference(sharedWithAtSign));
    // Set Encryption Keys for sharedWithAtSign
    await TestUtils.setEncryptionKeys(sharedWithAtSign);
    isSyncInProgress = true;
    sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });

  /// The purpose of this test verify the following:
  /// 1. notify method - notify a key to other atsign
  /// 3. Verifying that the notification status is delivered
  /// 2. Sync to cloud secondary
  /// 4. Get method - lookup verb in the sharedwith atsign
  /// 5. Verifying pubkeycs and sharedKeyEnc is not null
  test('notify a key to another atsign and verify the value in the receiver',
      () async {
    var uuid = Uuid();
    // Generate a v1 (time-based) id
    var randomValue = uuid.v4();
    var metadata = Metadata()..ttr = 864000;
    var codeKey = AtKey()
      ..key = 'loginCode$randomValue'
      ..sharedWith = sharedWithAtSign
      ..metadata = metadata;
    var value = '021365';
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    final notificationResult = await currentAtSignClientManager
        ?.notificationService
        .notify(NotificationParams.forUpdate(codeKey, value: value));
    expect(notificationResult, isNotNull);
    expect(notificationResult!.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    expect(notificationResult.atKey!.key, 'loginCode$randomValue.$namespace');
    expect(notificationResult.atKey!.sharedWith, codeKey.sharedWith);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    isSyncInProgress = true;
    sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    // Notify list result in the receiver's atsign
    var notificationListResult = await AtClientManager.getInstance()
        .atClient
        .notifyList(regex: 'loginCode$randomValue');
    expect(notificationListResult, isNotEmpty);
    notificationListResult = notificationListResult.replaceFirst('data:', '');
    final notificationListJson = jsonDecode(notificationListResult);
    print(notificationListJson);
    expect(notificationListJson[0]['from'], currentAtSign);
    expect(notificationListJson[0]['to'], sharedWithAtSign);
    expect(notificationListJson[0]['value'], isNotEmpty);
    var getResult = await sharedWithAtSignClientManager?.atClient.get(AtKey()
      ..key = 'loginCode$randomValue.$namespace'
      ..sharedBy = currentAtSign);
    print('get result is $getResult');
    expect(getResult!.value, value);
    expect(getResult.metadata?.sharedKeyEnc != null, true);
    expect(getResult.metadata?.pubKeyCS != null, true);
    //Setting the timeout to prevent termination of test
  }, timeout: Timeout(Duration(minutes: 5)));

  /// The purpose of this test verify the following:
  /// 1. notify method - notify a text to other atsign
  /// 3. Verifying that the notification status is delivered
  /// 2. Sync to cloud secondary
  /// 4. notify List - Verifying that the shared text exists in the receiver atsign
  test('notify a text to another atsign and verify the value in the receiver',
      () async {
    var uuid = Uuid();
    // Generate a v1 (time-based) id
    var randomValue = uuid.v4();
    var textToShare = 'Hello$randomValue';
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    final notificationResult = await currentAtSignClientManager
        ?.notificationService
        .notify(NotificationParams.forText(textToShare, sharedWithAtSign));
    expect(notificationResult, isNotNull);
    expect(notificationResult!.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    expect(notificationResult.atKey!.key, textToShare);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    isSyncInProgress = true;
    sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    var notifyListResult = await sharedWithAtSignClientManager?.atClient
        .notifyList(regex: textToShare);
    assert(
        notifyListResult!.contains('"key":"$sharedWithAtSign:$textToShare"'));
    //Setting the timeout to prevent termination of test
  }, timeout: Timeout(Duration(minutes: 5)));

  /// The purpose of this test verify the following:
  /// 1. notify method - notify a deletion of key to other atsign
  /// 3. Verifying that the notification status is delivered
  /// 2. Sync to cloud secondary
  /// 4. notify List - Verifying that the delete notification exists in the receiver
  test(
      'Notify a delete key with value to sharedWith atSign and listen for notification from sharedWith atSign',
      () async {
    var uuid = Uuid();
    // Generate a uuid
    var randomValue = uuid.v4();
    var delKey = AtKey()
      ..key = 'delKey$randomValue'
      ..sharedWith = sharedWithAtSign;

    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    final notificationResult = await currentAtSignClientManager
        ?.notificationService
        .notify(NotificationParams.forDelete(delKey));
    expect(notificationResult, isNotNull);
    expect(notificationResult!.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    var notificationListResult = await AtClientManager.getInstance()
        .atClient
        .notifyList(regex: 'delKey$randomValue');
    expect(notificationListResult, isNotEmpty);
    notificationListResult = notificationListResult.replaceFirst('data:', '');
    final notificationListJson = jsonDecode(notificationListResult);
    print(notificationListJson);
    expect(notificationListJson[0]['from'], currentAtSign);
    expect(notificationListJson[0]['to'], sharedWithAtSign);
    expect(notificationListJson[0]['operation'], 'delete');
    //Setting the timeout to prevent termination of test
  }, timeout: Timeout(Duration(minutes: 5)));

  tearDownAll(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}
