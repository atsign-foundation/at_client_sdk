import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() async {
  late AtClientManager currentAtClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['fourthAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace, authType: authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace, authType: authType);
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
      ..namespace = namespace;

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+1 100 200 30';
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
    final notificationResult = await currentAtClientManager
        .atClient.notificationService
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
