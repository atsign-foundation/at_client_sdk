import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

String currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
String sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
String authType = ConfigUtil.getYaml()['authType'];

const String constValue = '+91 9868123123';

void main() {
  String notifyKey =
      '$sharedWithAtSign:phone.${TestConstants.namespace}$currentAtSign';

  test('A test to send and receive notification with isolate', () async {
    ReceivePort mainIsolateReceivePort = ReceivePort('MainIsolateReceivePort');
    final listening = Completer<void>();
    final received = Completer<AtNotification>();

    // Spawn an isolate to listen for notifications
    Isolate childIsolate =
        await Isolate.spawn(initSharedAtSign, mainIsolateReceivePort.sendPort);
    // The child says it is listening once its monitor is up; anything else
    // it sends is the notification.
    mainIsolateReceivePort.listen((data) {
      if (data == 'listening') {
        listening.complete();
      } else if (!received.isCompleted) {
        received.complete(data as AtNotification);
      }
    });

    // Initialize another atSign to send notifications
    await TestSuiteInitializer.getInstance().testInitializer(
        currentAtSign, TestConstants.namespace, authType,
        enableInitialSync: false,
        atClientPreference: getAtClientPreferences(currentAtSign),
        posture: PqPosture.legacy);

    // NOTE: the child's subscribe() returns long before its monitor has
    // connected, and the atServer keeps no backlog for a monitor, so a
    // notification sent in that window reports delivered and never arrives.
    await listening.future.timeout(const Duration(seconds: 60));

    NotificationResult notificationResult = await AtClientManager.getInstance()
        .atClient
        .notificationService
        .notify(NotificationParams.forUpdate(AtKey.fromString(notifyKey),
            value: constValue));

    expect(notificationResult.notificationStatusEnum,
        NotificationStatusEnum.delivered);

    final data = await received.future.timeout(const Duration(seconds: 60));
    expect(data.value, constValue);
    expect(data.key, notifyKey);
    expect(data.from, currentAtSign);
    expect(data.to, sharedWithAtSign);
    childIsolate.kill();
  }, timeout: const Timeout(Duration(minutes: 3)));

  tearDown(() {
    // Remove hive directories
    Directory('test/hive/$currentAtSign').deleteSync(recursive: true);
    Directory('test/hive/$sharedWithAtSign').deleteSync(recursive: true);
  });
}

Future<void> initSharedAtSign(SendPort mainIsolateSendPort) async {
  await TestSuiteInitializer.getInstance().testInitializer(
      sharedWithAtSign, TestConstants.namespace, authType,
      enableInitialSync: false,
      atClientPreference: getAtClientPreferences(sharedWithAtSign),
      posture: PqPosture.legacy);

  final notifications =
      AtClientManager.getInstance().atClient.notificationService;
  notifications.subscribe(shouldDecrypt: true).listen((onData) {
    // Ignore stats notifications
    if (onData.value != constValue) {
      return;
    }
    mainIsolateSendPort.send(onData);
  });

  // Tell the sender once the monitor is up: subscribe() returns before it is.
  final service = notifications as NotificationServiceImpl;
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (service.currentListenerState != NotificationListenerState.listening) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('the monitor never reached listening within 60s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  mainIsolateSendPort.send('listening');
}

/// Builds the client preferences for a spawned isolate, which cannot reach the
/// `TestPreferences` singleton, so the posture is named here.
AtClientPreference getAtClientPreferences(String atSign) {
  var atClientPreference = AtClientPreference(posture: PqPosture.legacy);
  atClientPreference.hiveStoragePath = 'test/hive/$atSign';
  atClientPreference.commitLogPath = 'test/hive/$atSign/commit/';
  atClientPreference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
  atClientPreference.rootPort =
      ConfigUtil.getYaml()['root_server']['port'] ?? 64;
  // NOTE: the one route in this pack that reaches a live client without going
  // through TestPreferences, so the guard is invoked by hand.
  TestPreferences.refuseDurableWritesToLongLivedAtSigns(
      atSign, atClientPreference);
  return atClientPreference;
}
