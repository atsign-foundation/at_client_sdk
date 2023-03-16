import 'dart:io';
import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  var currentAtSign = '@alice🛠';
  var sharedWithAtSign = '@bob🛠';
  late AtClientManager atClientManager;
  String namespace = 'wavi';
  setUpAll(() async {
    var preference = TestUtils.getPreference(currentAtSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, 'wavi', preference);
    atClientManager.atClient.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(currentAtSign, preference);
  });
  test('notify updating of a key to sharedWith atSign - using await', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var value = '+1 100 200 300';

    var result = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    print('NotificationId : ${result.notificationID}');
    expect(result.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(result.atKey?.key, 'phone');
    expect(result.atKey?.sharedWith, phoneKey.sharedWith);
    // fetch notification using notify fetch
    var atNotification = await atClientManager.atClient.notificationService
        .fetch(result.notificationID);
    expect(atNotification.key, phoneKey.toString());
    expect(atNotification.status, 'NotificationStatus.delivered');
    expect(atNotification.messageType, 'MessageType.key');
    expect(atNotification.operation, 'OperationType.update');
  });

  test(
      'notify updating of a key to sharedWith atSign - get status using the notification Id',
      () async {
    // phone.me@alice🛠
    var lastNumber = Random().nextInt(30);
    var landlineKey = AtKey()
      ..key = 'landline'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var value = '040-238989$lastNumber';

    var result = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forUpdate(landlineKey, value: value));
    print('NotificationId : ${result.notificationID}');
    final notificationStatus = await atClientManager
        .atClient.notificationService
        .getStatus(result.notificationID);
    print('Notification status is $notificationStatus');
    expect(notificationStatus.notificationID, result.notificationID);
    expect(notificationStatus.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    expect(result.atKey?.key, 'landline');
    expect(result.atKey?.sharedWith, landlineKey.sharedWith);
  });

  test('notify updating of a key to sharedWith atSign - using callback',
      () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var value = '+1 100 200 300';
    await atClientManager.atClient.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
  });

  test('notify deletion of a key to sharedWith atSign', () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var notificationResult = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forDelete(phoneKey));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey?.key, 'phone');
    expect(notificationResult.atKey?.sharedWith, phoneKey.sharedWith);
  });

  test('notify deletion of a key to sharedWith atSign - callback', () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠'
      ..namespace = namespace;
    await atClientManager.atClient.notificationService.notify(
        NotificationParams.forDelete(phoneKey),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify text of to sharedWith atSign', () async {
    var notificationResult = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forText('Hello', sharedWithAtSign));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey?.key, 'Hello');
    expect(notificationResult.atKey?.sharedWith, sharedWithAtSign);
  });

  test('notify text of to sharedWith atSign with shouldEncrypt set to true',
      () async {
    var notificationResult = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forText('Hello', sharedWithAtSign,
            shouldEncrypt: true));
    expect(notificationResult.notificationStatusEnum.toString(),
        'NotificationStatusEnum.delivered');
    expect(notificationResult.atKey?.key, 'Hello');
    expect(notificationResult.atKey?.sharedWith, sharedWithAtSign);
  });

  test('notify text of to sharedWith atSign - callback', () async {
    await atClientManager.atClient.notificationService.notify(
        NotificationParams.forText('phone', '@bob🛠'),
        onSuccess: onSuccessCallback);
    await Future.delayed(Duration(seconds: 10));
  });

  test('notify - test deprecated method using notification service', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var value = '+1 100 200 300';
    final atClient = atClientManager.atClient;
    final notifyResult =
        await atClient.notify(phoneKey, value, OperationEnum.update);
    expect(notifyResult, true);
  });
  // test('notifyall - test deprecated method using notificationservice',
  //     () async {
  //   final bobAtSign = '@bob🛠';
  //   final colinAtSign = '@colin🛠';
  //   // phone.me@alice🛠
  //   var shareWithList = []
  //     ..add(bobAtSign)
  //     ..add(colinAtSign);
  //   var phoneKey = AtKey()
  //     ..key = 'phone'
  //     ..sharedWith = jsonEncode(shareWithList)
  //   ..namespace = '.wavi';
  //   var value = '+1 100 200 300';
  //   final atClient = atClientManager.atClient;
  //   final notifyResult =
  //       await atClient.notifyAll(phoneKey, value, OperationEnum.update);
  //   expect(jsonDecode(notifyResult)['@bobAtSign'], true);
  //   expect(jsonDecode(notifyResult)['@colinAtSign'], true);
  // });
  test('notify check value decryption on receiver', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var value = '+1 100 200 300';
    await atClientManager.atClient.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    var preference = TestUtils.getPreference(sharedWithAtSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, 'wavi', preference);
    atClientManager.atClient.notificationService
        .subscribe(regex: 'phone')
        .listen((event) {
      print('got receiver notification');
      print(event);
    });
    Future.delayed(Duration(seconds: 10));
  });

  test('A test to fetch non existent notification', () async {
    var atNotification =
        await atClientManager.atClient.notificationService.fetch('abc-123');
    expect(atNotification.id, 'abc-123');
    expect(atNotification.status, 'NotificationStatus.expired');
  });

  test('A test to verify the notification expiry', () async {
    for (int i = 0; i < 10; i++) {
      print('Testing notification expiry - test run #$i');
      var atKey = (AtKey.shared('test-notification-expiry',
          namespace: 'wavi', sharedBy: currentAtSign)
        ..sharedWith(sharedWithAtSign))
          .build();
      NotificationResult notificationResult = await atClientManager
          .atClient.notificationService
          .notify(NotificationParams.forUpdate(atKey,
          notificationExpiry: Duration(days: 7)));

      AtNotification atNotification = await AtClientManager
          .getInstance()
          .atClient
          .notificationService
          .fetch(notificationResult.notificationID);

      print ('Fetched notification $atNotification');

      var actualExpiresAtInEpochMills = DateTime
          .fromMillisecondsSinceEpoch(
          atNotification.expiresAtInEpochMillis!)
          .toUtc()
          .millisecondsSinceEpoch;
      var expectedExpiresAtInEpochMills =
          DateTime
              .fromMillisecondsSinceEpoch(atNotification.epochMillis)
              .toUtc()
              .add(Duration(minutes: 1))
              .millisecondsSinceEpoch;
      expect((actualExpiresAtInEpochMills - expectedExpiresAtInEpochMills).abs() < 10, true);
    }
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
