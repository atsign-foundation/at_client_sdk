import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  test('notify updating of a key to sharedWith atSign - using await', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var notification = await NotificationServiceImpl.create(atClient,
        atClientManager: atClientManager);
    var result = await notification
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    expect(result.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(result.atKey.key, 'phone');
    expect(result.atKey.sharedWith, phoneKey.sharedWith);
  });

  test('notify updating of a key to sharedWith atSign - using callback',
      () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    await atClientManager.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
  });

  test('notify deletion of a key to sharedWith atSign', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var notificationResult = await atClientManager.notificationService
        .notify(NotificationParams.forDelete(phoneKey));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey.key, 'phone');
    expect(notificationResult.atKey.sharedWith, phoneKey.sharedWith);
  });

  test('notify deletion of a key to sharedWith atSign - callback', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    await atClientManager.notificationService.notify(
        NotificationParams.forDelete(phoneKey),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify text of to sharedWith atSign', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    var notification = await NotificationServiceImpl.create(atClient,
        atClientManager: atClientManager);
    var notificationResult = await notification
        .notify(NotificationParams.forText('Hello', '@bob🛠'));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey.key, 'Hello');
    expect(notificationResult.atKey.sharedWith, '@bob🛠');
  });

  test('notify text of to sharedWith atSign - callback', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    await atClientManager.notificationService.notify(
        NotificationParams.forText('phone', '@bob🛠'),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify - test deprecated method using notificationservice', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    final atClient = atClientManager.atClient;
    final notifyResult =
        await atClient.notify(phoneKey, value, OperationEnum.update);
    expect(notifyResult, true);
  });
  test('notifyall - test deprecated method using notificationservice',
      () async {
    final aliceAtSign = '@alice🛠';
    final bobAtSign = '@bob🛠';
    final colinAtSign = '@colin🛠';
    final alicePreference = TestUtils.getPreference(aliceAtSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(aliceAtSign, 'me', alicePreference);
    // To setup encryption keys
    await setEncryptionKeys(aliceAtSign, alicePreference);
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
  tearDown(() async => await tearDownFunc());
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
