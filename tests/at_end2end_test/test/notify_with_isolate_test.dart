import 'dart:io';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
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

    // Spawn an isolate to listen for notifications
    Isolate childIsolate =
        await Isolate.spawn(initSharedAtSign, mainIsolateReceivePort.sendPort);
    // Listen for messages from isolate
    mainIsolateReceivePort.listen(expectAsync1((data) {
      expect(data.value, constValue);
      expect(data.key, notifyKey);
      expect(data.from, currentAtSign);
      expect(data.to, sharedWithAtSign);
      childIsolate.kill();
    }));

    // Initialize another atSign to send notifications
    await TestSuiteInitializer.getInstance().testInitializer(
        currentAtSign, TestConstants.namespace, authType,
        enableInitialSync: false,
        atClientPreference: getAtClientPreferences(currentAtSign),
            posture: PqPosture.legacy);

    NotificationResult notificationResult = await AtClientManager.getInstance()
        .atClient
        .notificationService
        .notify(NotificationParams.forUpdate(AtKey.fromString(notifyKey),
            value: constValue));

    expect(notificationResult.notificationStatusEnum,
        NotificationStatusEnum.delivered);
  });

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

  AtClientManager.getInstance()
      .atClient
      .notificationService
      .subscribe(shouldDecrypt: true)
      .listen((onData) {
    // Ignore stats notifications
    if (onData.value != constValue) {
      return;
    }
    mainIsolateSendPort.send(onData);
  });
}

/// Built here rather than through `TestPreferences`, because this runs inside
/// a spawned isolate with no access to that singleton — so the posture is named
/// here too. No compiler names this site: it constructs the preference
/// directly, and `AtClientPreference.posture` has a default.
AtClientPreference getAtClientPreferences(String atSign) {
  var atClientPreference = AtClientPreference(posture: PqPosture.legacy);
  atClientPreference.hiveStoragePath = 'test/hive/$atSign';
  atClientPreference.commitLogPath = 'test/hive/$atSign/commit/';
  atClientPreference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
  atClientPreference.rootPort = ConfigUtil.getYaml()['root_server']['port'] ?? 64;
  // The one route in this pack that reaches a live client without passing
  // through TestPreferences or testInitializer, so the guard is invoked by
  // hand. Leaving it out would make this file the single hole in a rule the
  // rest of the suite cannot break.
  TestPreferences.refuseDurableWritesToLongLivedAtSigns(
      atSign, atClientPreference);
  return atClientPreference;
}
