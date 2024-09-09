import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace);
    atClientManager.atClient.syncService.sync();
  });
  // Invoking 'setCurrentAtSign' in setUp method to set currentAtSign before each test.
  setUp(() async {
    print('Setting current atSign to $currentAtSign');
    atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, 'wavi', TestUtils.getPreference(currentAtSign));
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

  test('verify unencrypted value is returned when encryptValue is set to false',
      () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace;
    var value = '+1 100 200 300';
    var notificationResult = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value),
            encryptValue: false);
    var notificationId = notificationResult.notificationID;
    var notification = await atClientManager.atClient.notificationService
        .fetch(notificationId);
    print('Notification ID: ${notification.id}');
    print('Notification value: ${notification.value}');
    print('Notification key: ${notification.key}');
    expect(notification.value, value);
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
      print('atKey: $atKey');
      atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign, 'wavi', TestUtils.getPreference(currentAtSign));

      NotificationResult notificationResult = await atClientManager
          .atClient.notificationService
          .notify(NotificationParams.forUpdate(atKey,
              notificationExpiry: Duration(minutes: 1)));

      print('notificationResult: $notificationResult');
      print(
          'notificationResult.atClientException: ${notificationResult.atClientException}');

      AtNotification atNotification = await atClientManager
          .atClient.notificationService
          .fetch(notificationResult.notificationID);

      print('Fetched notification $atNotification');

      var actualExpiresAtInEpochMills = DateTime.fromMillisecondsSinceEpoch(
              atNotification.expiresAtInEpochMillis!)
          .toUtc()
          .millisecondsSinceEpoch;
      var expectedExpiresAtInEpochMills =
          DateTime.fromMillisecondsSinceEpoch(atNotification.epochMillis)
              .toUtc()
              .add(Duration(minutes: 1))
              .millisecondsSinceEpoch;
      expect(
          (actualExpiresAtInEpochMills - expectedExpiresAtInEpochMills).abs() <
              10,
          true);
    }
  });

  group('A group of tests for notification fetch', () {
    test('A test to verify non existent notification', () async {
      await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
      var notificationResult = await AtClientManager.getInstance()
          .atClient
          .notificationService
          .fetch('abc-123');
      expect(notificationResult.id, 'abc-123');
      expect(notificationResult.status, 'NotificationStatus.expired');
    });

    test('A test to verify the notification expiry', () async {
      for (int i = 0; i < 10; i++) {
        print('Testing notification expiry - test run #$i');
        await AtClientManager.getInstance().setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
        var atKey = (AtKey.shared('test-notification-expiry',
                namespace: 'wavi', sharedBy: currentAtSign)
              ..sharedWith(sharedWithAtSign))
            .build();
        NotificationResult notificationResult =
            await AtClientManager.getInstance()
                .atClient
                .notificationService
                .notify(NotificationParams.forUpdate(atKey,
                    notificationExpiry: Duration(minutes: 1)));

        AtNotification atNotification = await AtClientManager.getInstance()
            .atClient
            .notificationService
            .fetch(notificationResult.notificationID);

        var actualExpiresAtInEpochMills = DateTime.fromMillisecondsSinceEpoch(
                atNotification.expiresAtInEpochMillis!)
            .toUtc()
            .millisecondsSinceEpoch;
        var expectedExpiresAtInEpochMills =
            DateTime.fromMillisecondsSinceEpoch(atNotification.epochMillis)
                .toUtc()
                .add(Duration(minutes: 1))
                .millisecondsSinceEpoch;
        expect(
            (actualExpiresAtInEpochMills - expectedExpiresAtInEpochMills)
                    .abs() <
                10,
            true);
      }
    });
  });
}

void onSuccessCallback(notificationResult) {
  expect(notificationResult.notificationStatusEnum.toString(),
      'NotificationStatusEnum.delivered');
  expect(notificationResult.atKey.key, 'phone');
  expect(notificationResult.atKey.sharedWith, '@bob🛠');
}
