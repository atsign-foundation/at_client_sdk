import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';

void main() async {
  late AtClientManager currentAtClientManager;
  late AtClientManager sharedWithAtClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
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
      ..metadata = (Metadata()..ttr = 60000)
      ..namespace = 'e2etest';

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+1 100 200 30';
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
    final notificationResult = await currentAtClientManager.notificationService
        .notify(NotificationParams.forUpdate(phoneKey, value: value));
    expect(notificationResult, isNotNull);
    expect(notificationResult.notificationStatusEnum,
        NotificationStatusEnum.delivered);

    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign));
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
  }, timeout: Timeout(Duration(minutes: 1)));

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
            currentAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));

        var epochMillsNow = DateTime.now().millisecondsSinceEpoch;
        var notificationResult = await AtClientManager.getInstance()
            .notificationService
            .notify(input);

        expect(notificationResult.notificationStatusEnum,
            NotificationStatusEnum.delivered);

        sharedWithAtClientManager = await AtClientManager.getInstance().setCurrentAtSign(sharedWithAtSign,
            namespace, TestPreferences.getInstance().getPreference(sharedWithAtSign));
        var atNotification = await AtClientManager.getInstance()
            .notificationService
            .fetch(notificationResult.notificationID);
        atNotification.isEncrypted = input.atKey.metadata!.isEncrypted;
        await NotificationResponseTransformer(sharedWithAtClientManager.atClient).transform(Tuple()
          ..one = atNotification
          ..two = (NotificationConfig()
            ..shouldDecrypt = input.atKey.metadata!.isEncrypted!));
        expect(atNotification.id, notificationResult.notificationID);
        expect(atNotification.key, expectedOutput);
      });
    });
  });

  group('A group of tests for notification fetch', () {
    test('A test to verify non existent notification', () async {
      await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign, namespace, TestPreferences.getInstance().getPreference(currentAtSign));
      var notificationResult = await AtClientManager.getInstance()
          .notificationService
          .fetch('abc-123');
      expect(notificationResult.id, 'abc-123');
      expect(notificationResult.status, 'NotificationStatus.expired');
    });
  });

  tearDownAll(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}

/// Class responsible for getting the notifications from the cloud secondary
class MonitorForNotification {
  String notificationId;
  String atSign;
  int epochMillsNow;
  StreamController streamController;
  Monitor? monitor;

  MonitorForNotification(this.notificationId, this.atSign, this.epochMillsNow,
      this.streamController);

  Future<void> init() async {
    monitor = Monitor(
        _onMonitorSuccess,
        _onMonitorError,
        atSign,
        TestPreferences.getInstance().getPreference(atSign),
        MonitorPreference()
          ..lastNotificationTime = epochMillsNow
          ..keepAlive = false,
        _onMonitorRetry);

    await monitor?.start(lastNotificationTime: epochMillsNow);
  }

  Future<void> _onMonitorSuccess(String notificationStr) async {
    if (notificationStr.contains(notificationId)) {
      final notificationResponseParser = NotificationResponseParser();
      final atNotifications =
          await notificationResponseParser.getAtNotifications(
              notificationResponseParser.parse(notificationStr));
      for (var element in atNotifications) {
        streamController.add(element);
      }
      monitor?.stop();
    }
  }

  //Dummy implementation for error
  void _onMonitorError(arg1) {
    print(arg1);
  }

  // Dummy implementation for retry callback
  void _onMonitorRetry() {}
}