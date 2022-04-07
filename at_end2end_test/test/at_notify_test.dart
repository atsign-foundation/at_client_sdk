import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

// ignore: prefer_typing_uninitialized_variables
void main() {
  var currentAtSign, sharedWithAtSign, sharedWithAtSign1;
  AtClientManager? currentAtSignClientManager, sharedWithAtSignClientManager;
  var namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    sharedWithAtSign1 = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
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

  test('notify a key to another atsign and verify the value in the receiver', () async {
    var lastNumber = Random().nextInt(30);
    var metadata = Metadata()
    ..ttr = 864000;
    var codeKey = AtKey()
      ..key = 'code'
      ..sharedWith = sharedWithAtSign
      ..metadata = metadata;
    var value = '99 09 $lastNumber';
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    final notificationResult = await currentAtSignClientManager?.notificationService.notify(NotificationParams.forUpdate(codeKey, value: value));
    expect(notificationResult, isNotNull);
    expect(notificationResult!.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    expect(notificationResult.atKey.key, 'code.$namespace');
    expect(notificationResult.atKey.sharedWith, codeKey.sharedWith);
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
    var getResult = await sharedWithAtSignClientManager?.atClient.get(AtKey()
      ..key = 'code.$namespace'
      ..sharedBy = currentAtSign);
    print('get result is $getResult');
    expect( getResult!.value,value);
    expect(getResult.metadata?.sharedKeyEnc != null, true);
    expect(getResult.metadata?.pubKeyCS != null, true);
  }, timeout: Timeout(Duration(seconds: 120)));

  test('notify a text to another atsign and verify the value in the receiver', () async {
    var textToShare = 'Hello';
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    final notificationResult = await currentAtSignClientManager?.notificationService.notify(NotificationParams.forText(textToShare, sharedWithAtSign));
    expect(notificationResult, isNotNull);
    expect(notificationResult!.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    expect(notificationResult.atKey.key, textToShare);
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
    var notifyListResult = await sharedWithAtSignClientManager?.atClient.notifyList(regex: 'Hello');
    assert(notifyListResult!.contains('"key":"$sharedWithAtSign:$textToShare"'));
  }, timeout: Timeout(Duration(seconds: 120)));
  
}
