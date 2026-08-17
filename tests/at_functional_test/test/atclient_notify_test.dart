import 'dart:async';
import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'test_utils.dart';

// ignore_for_file: deprecated_member_use
void main() {
  late AtClientManager atClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';
  late AtSignLogger logger;

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    atClientManager = await TestUtils.initAtClient(sharedWithAtSign, namespace);
    atClientManager.atClient.syncService.sync();

    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace);
    atClientManager.atClient.syncService.sync();

    logger = AtSignLogger(' atclient_notify_test ');
  });

  setUp(() async {
    // Invoking 'setCurrentAtSign' in setUp method to set currentAtSign before each test.
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
    final notificationStatus = await atClientManager
        .atClient.notificationService
        .getStatus(result.notificationID);
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
    var notificationResult = await atClientManager.atClient.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    var notification = await atClientManager.atClient.notificationService
        .fetch(notificationResult.notificationID);
    // encrypted value should not be equal to actual value
    expect(notification.value == value, false);
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
    Completer received = Completer();
    await atClientManager.atClient.notificationService
        .notify(NotificationParams.forDelete(phoneKey),
            onSuccess: (NotificationResult notificationResult) {
      expect(notificationResult.notificationStatusEnum.toString(),
          'NotificationStatusEnum.delivered');
      expect(notificationResult.atKey?.key, 'phone');
      expect(notificationResult.atKey?.sharedWith, '@bob🛠');
      received.complete();
    });
    await received.future;
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
    Completer received = Completer();
    await atClientManager.atClient.notificationService
        .notify(NotificationParams.forText('phone', '@bob🛠'),
            onSuccess: (NotificationResult notificationResult) {
      expect(notificationResult.notificationStatusEnum.toString(),
          'NotificationStatusEnum.delivered');
      expect(notificationResult.atKey?.key, 'phone');
      expect(notificationResult.atKey?.sharedWith, '@bob🛠');
      received.complete();
    });
    await received.future;
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
    // First off, let's initialize local storage and lastNotificationTime
    // for the receiving atSign
    logger.info('Switching to $sharedWithAtSign');
    atClientManager = await atClientManager.setCurrentAtSign(
        sharedWithAtSign, 'wavi', TestUtils.getPreference(sharedWithAtSign));
    atClientManager.atClient.notificationService.subscribe(regex: 'nothing');

    int? lnt;
    int count = 0;
    while (lnt == null && count < 50) {
      lnt = await (atClientManager.atClient.notificationService
              as NotificationServiceImpl)
          .getLastNotificationTime();
      if (lnt == null) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      count++;
    }

    expect(lnt, isNotNull, reason: 'lastNotificationTime should not be null');

    logger.info('Switching to $currentAtSign');
    // Switch to the sending atSign
    atClientManager = await atClientManager.setCurrentAtSign(
        currentAtSign, 'wavi', TestUtils.getPreference(currentAtSign));

    logger.info('Sending notification');
    // And send a notification
    var sentValue = '+1 100 200 300';
    await atClientManager.atClient.notificationService.notify(
      NotificationParams.forUpdate(
          AtKey.fromString(
              '$sharedWithAtSign:${Uuid().v4()}.phones.$namespace$currentAtSign'),
          value: sentValue),
      waitForFinalDeliveryStatus: false,
      checkForFinalDeliveryStatus: false,
    );

    logger.info('Switching to $sharedWithAtSign');
    // Switch to the receiving atSign
    atClientManager = await atClientManager.setCurrentAtSign(
        sharedWithAtSign, 'wavi', TestUtils.getPreference(sharedWithAtSign));

    logger.info('Subscribing to notifications');
    // and subscribe to notifications
    Completer<String> received = Completer<String>();
    atClientManager.atClient.notificationService
        .subscribe(regex: '.*\\.phones\\.$namespace', shouldDecrypt: true)
        .listen((event) {
      if (event.value == sentValue) {
        received.complete(event.value!);
      } else {
        received.completeError('Expected $sentValue but got ${event.value}');
      }
    });
    await received.future;
  });

  /// `send()` had no live coverage at all, so nothing exercised the command it
  /// puts on the wire — which is its own command, not the one `notify()` sends.
  ///
  /// Two things this catches that no unit test can: that the atServer accepts
  /// the command this path builds, and that the name survives being split
  /// across the AtKey's `key` and `namespace` fields. `send()` names a record
  /// with a single string and the split is at the FIRST dot, so a regression
  /// there puts a truncated key on the wire and no recipient regex matches it.
  test('send() delivers, and the name it puts on the wire is the whole name',
      () async {
    // Run-unique: the id half separates this run's record from the last one's,
    // which matters because the recipient matches on the namespace half.
    final id = Uuid().v4();
    const sendNamespace = 'sendlive.wavi';
    final sentValue = 'send-live-${Random().nextInt(1000000)}';

    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));

    final notificationId = await AtClientManager.getInstance()
        .atClient
        .notificationService
        .send(
            to: sharedWithAtSign.toAtsign(),
            idAndNamespace: '$id.$sendNamespace',
            body: sentValue);

    // The sender's own atServer stored it, which is the command being accepted
    // — a rejected notify would not be here to fetch.
    final stored = await AtClientManager.getInstance()
        .atClient
        .notificationService
        .fetch(notificationId);
    expect(stored.key, '$sharedWithAtSign:$id.$sendNamespace$currentAtSign',
        reason: 'the whole name must reach the wire. The AtKey holds it split '
            'across key and namespace, and a builder writing only the key '
            'field would put "$id" here — which no recipient regex matches');

    logger.info('Switching to $sharedWithAtSign');
    atClientManager = await atClientManager.setCurrentAtSign(
        sharedWithAtSign, 'wavi', TestUtils.getPreference(sharedWithAtSign));

    final received = Completer<String>();
    final subscription = atClientManager.atClient.notificationService
        .subscribe(regex: '.*\\.$sendNamespace', shouldDecrypt: true)
        .listen((event) {
      if (event.key.contains(id) && !received.isCompleted) {
        received.complete(event.value ?? '');
      }
    });
    addTearDown(subscription.cancel);

    expect(await received.future.timeout(Duration(seconds: 60)), sentValue,
        reason: 'and it arrives decrypted — the body is encrypted under the '
            'namespace half of the name, so a send resolving the wrong '
            'namespace would be opened with the wrong key');
  });

  test('A test to fetch non existent notification', () async {
    var atNotification =
        await atClientManager.atClient.notificationService.fetch('abc-123');
    expect(atNotification.id, 'abc-123');
    expect(atNotification.status, 'NotificationStatus.expired');
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
      await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
      for (int i = 0; i < 10; i++) {
        logger.info('Testing notification expiry - test run #$i');
        var atKey = (AtKey.shared('test-notification-expiry',
                namespace: 'wavi', sharedBy: currentAtSign)
              ..sharedWith(sharedWithAtSign))
            .build();
        NotificationResult notificationResult =
            await AtClientManager.getInstance()
                .atClient
                .notificationService
                .notify(
                  NotificationParams.forUpdate(atKey,
                      notificationExpiry: Duration(minutes: 1)),
                  waitForFinalDeliveryStatus: false,
                  checkForFinalDeliveryStatus: false,
                );

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
