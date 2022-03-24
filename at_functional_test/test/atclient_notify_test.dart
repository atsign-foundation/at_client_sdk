import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  var currentAtSign = '@alice🛠';
  var sharedWithAtSign = '@bob🛠';
  late AtClientManager atClientManager;
  setUpAll(() async {
    var preference = TestUtils.getPreference(currentAtSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, 'me', preference);
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(currentAtSign, preference);
  });
  test('notify updating of a key to sharedWith atSign - using await', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign;
    var value = '+1 100 200 300';

    var result = await atClientManager.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    print('NotificationId : ${result.notificationID}');
    expect(result.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(result.atKey?.key, 'phone');
    expect(result.atKey?.sharedWith, phoneKey.sharedWith);
  });

  test('notify updating of a key to sharedWith atSign - using callback',
      () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign;
    var value = '+1 100 200 300';
    await atClientManager.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
  });

  test('notify deletion of a key to sharedWith atSign', () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign;
    var notificationResult = await atClientManager.notificationService
        .notify(NotificationParams.forDelete(phoneKey));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey?.key, 'phone');
    expect(notificationResult.atKey?.sharedWith, phoneKey.sharedWith);
  });

  test('notify deletion of a key to sharedWith atSign - callback', () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    await atClientManager.notificationService.notify(
        NotificationParams.forDelete(phoneKey),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify text of to sharedWith atSign', () async {
    var notificationResult = await atClientManager.notificationService
        .notify(NotificationParams.forText('Hello', sharedWithAtSign));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey?.key, 'Hello');
    expect(notificationResult.atKey?.sharedWith, sharedWithAtSign);
  });

  test('notify text of to sharedWith atSign - callback', () async {
    await atClientManager.notificationService.notify(
        NotificationParams.forText('phone', '@bob🛠'),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify - test deprecated method using notificationservice', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign;
    var value = '+1 100 200 300';
    final atClient = atClientManager.atClient;
    final notifyResult =
        await atClient.notify(phoneKey, value, OperationEnum.update);
    expect(notifyResult, true);
  });
  test('notifyall - test deprecated method using notificationservice',
      () async {
    final bobAtSign = '@bob🛠';
    final colinAtSign = '@colin🛠';
    // phone.me@alice🛠
    var shareWithList = []
      ..add(bobAtSign)
      ..add(colinAtSign);
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = jsonEncode(shareWithList);
    var value = '+1 100 200 300';
    final atClient = atClientManager.atClient;
    final notifyResult =
        await atClient.notifyAll(phoneKey, value, OperationEnum.update);
    expect(jsonDecode(notifyResult)[bobAtSign], true);
    expect(jsonDecode(notifyResult)[colinAtSign], true);
  });
  tearDownAll(() async => await tearDownFunc());
}

void onSuccessCallback(notificationResult) {
  expect(notificationResult.notificationStatusEnum.toString(),
      'NotificationStatusEnum.delivered');
  expect(notificationResult.atKey.key, 'phone');
  expect(notificationResult.atKey.sharedWith, '@bob🛠');
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
