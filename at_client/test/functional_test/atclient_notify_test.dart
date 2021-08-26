import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  test('notify updating of a key to sharedWith atSign - using await', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient!.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var notification = NotificationServiceImpl.create(atClient);
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
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient!.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var notification = NotificationServiceImpl.create(atClient);
    notification.notify(NotificationParams.forUpdate(phoneKey, value: value));
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify deletion of a key to sharedWith atSign', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient!.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var notification = NotificationServiceImpl.create(atClient);
    var notificationResult =
        await notification.notify(NotificationParams.forDelete(phoneKey));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey.key, 'phone');
    expect(notificationResult.atKey.sharedWith, phoneKey.sharedWith);
  });

  test('notify deletion of a key to sharedWith atSign - callback', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient!.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var notification = NotificationServiceImpl.create(atClient);
    notification.notify(NotificationParams.forDelete(phoneKey),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify text of to sharedWith atSign', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient!.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    var notification = NotificationServiceImpl.create(atClient);
    var notificationResult = await notification
        .notify(NotificationParams.forText('Hello', '@bob🛠'));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey.key, 'Hello');
    expect(notificationResult.atKey.sharedWith, '@bob🛠');
  });

  test('notify text of to sharedWith atSign - callback', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient!.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    var notification = NotificationServiceImpl.create(atClient);
    notification.notify(NotificationParams.forText('phone', '@bob🛠'),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
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

AtClientPreference getAlicePreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.syncStrategy = SyncStrategy.IMMEDIATE;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
