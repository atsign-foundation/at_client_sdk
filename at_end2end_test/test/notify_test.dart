import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';
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

  test(
      'Notify a key with value to sharedWith atSign and listen for notification from sharedWith atSign',
      () async {
    var uuid = Uuid();
    // Generate  uuid
    var randomValue = uuid.v4();
    var phoneKey = AtKey()
      ..key = 'phone$randomValue'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata()..ttr = 60000);

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+1 100 200 30';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    final notificationResult = await currentAtSignClientManager
        ?.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    expect(notificationResult, isNotNull);
    expect(notificationResult!.notificationStatusEnum,
        NotificationStatusEnum.delivered);
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    var notificationListResult = await AtClientManager.getInstance()
        .atClient
        .notifyList(regex: 'phone$randomValue');
    expect(notificationListResult, isNotEmpty);
    notificationListResult = notificationListResult.replaceFirst('data:', '');
    final notificationListJson = jsonDecode(notificationListResult);
    print(notificationListJson);
    expect(notificationListJson[0]['from'], currentAtSign);
    expect(notificationListJson[0]['to'], sharedWithAtSign);
    expect(notificationListJson[0]['value'], isNotEmpty);
  });

  /// The purpose of this test is to verify the notify text with setting
  /// shouldEncrypt parameter to true (which encrypt the notify text)
  /// and setting shouldEncrypt to false (text message is sent as plain text).
  group('A group of tests to verify notification text', () {
    var notifyText = 'Hello How are you';
    var whomToNotify = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    var inputToExpectedOutput = {
      // Encrypt the notify text data
      NotificationParams.forText('$notifyText', whomToNotify,
          shouldEncrypt: true): '$whomToNotify:$notifyText',
      // Send notify text message as plain text
      NotificationParams.forText('$notifyText', whomToNotify,
          shouldEncrypt: false): '$whomToNotify:$notifyText'
    };
    inputToExpectedOutput.forEach((input, expectedOutput) {
      test('Setting shouldEncrypt to ${input.atKey.metadata?.isEncrypted}',
          () async {
        // Setting the AtClientManager instance to current atsign
        await AtClientManager.getInstance().setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));

        var notificationResult = await AtClientManager.getInstance()
            .notificationService
            .notify(input);
        print(notificationResult.notificationID);
        expect(notificationResult.notificationStatusEnum,
            NotificationStatusEnum.delivered);

        // Setting the AtClientManager instance to sharedWith atsign
        await AtClientManager.getInstance().setCurrentAtSign(sharedWithAtSign,
            namespace, TestUtils.getPreference(sharedWithAtSign));
        // Getting the notification from notify:list command
        var notificationListResponse = await AtClientManager.getInstance()
            .atClient
            .getRemoteSecondary()
            ?.executeCommand('notify:list\n', auth: true);
        notificationListResponse =
            notificationListResponse?.replaceFirst('data:', '');
        List notificationListJSON = jsonDecode(notificationListResponse!);
        // Filter the notification using the notification Id.
        notificationListJSON.retainWhere(
            (element) => element['id'] == notificationResult.notificationID);
        expect(notificationListJSON.length, 1);
        var response = await NotificationResponseTransformer().transform(Tuple()
          ..one = AtNotification(
              notificationListJSON.first['id'],
              notificationListJSON.first['key'],
              notificationListJSON.first['from'],
              notificationListJSON.first['to'],
              notificationListJSON.first['epochMillis'],
              notificationListJSON.first['messageType'],
              notificationListJSON.first['isEncrypted'])
          ..two = (NotificationConfig()..shouldDecrypt = true));
        expect(response.key, expectedOutput);
      });
    });
  });

  tearDownAll(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}
