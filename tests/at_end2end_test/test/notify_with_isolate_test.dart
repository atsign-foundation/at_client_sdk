import 'dart:io';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';

String currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
String sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
String authType = ConfigUtil.getYaml()['authType'];

void main() {
  String notifyKey =
      '$sharedWithAtSign:phone.${TestConstants.namespace}$currentAtSign';
  String value = '+91 9868123123';

  test('A test to send and receive notification with isolate', () async {
    ReceivePort mainIsolateReceivePort = ReceivePort('MainIsolateReceivePort');

    // Spawn an isolate to listen for notifications
    Isolate childIsolate =
        await Isolate.spawn(initSharedAtSign, mainIsolateReceivePort.sendPort);
    // Listen for messages from isolate
    mainIsolateReceivePort.listen(expectAsync1((data) {
      expect(data.value, value);
      expect(data.key, notifyKey);
      expect(data.from, currentAtSign);
      expect(data.to, sharedWithAtSign);
      childIsolate.kill();
    }));

    // Initialize another atSign to send notifications
    await TestSuiteInitializer.getInstance().testInitializer(
        currentAtSign, TestConstants.namespace, authType,
        enableInitialSync: false,
        atClientPreference: getAtClientPreferences(currentAtSign));

    NotificationResult notificationResult = await AtClientManager.getInstance()
        .atClient
        .notificationService
        .notify(NotificationParams.forUpdate(AtKey.fromString(notifyKey),
            value: value));

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
      atClientPreference: getAtClientPreferences(sharedWithAtSign));

  AtClientManager.getInstance()
      .atClient
      .notificationService
      .subscribe(shouldDecrypt: true)
      .listen((onData) {
    // Ignore stats notifications
    if (onData.id == '-1') {
      return;
    }
    mainIsolateSendPort.send(onData);
  });
}

AtClientPreference getAtClientPreferences(String atSign) {
  var atClientPreference = AtClientPreference();
  atClientPreference.hiveStoragePath = 'test/hive/$atSign';
  atClientPreference.commitLogPath = 'test/hive/$atSign/commit/';
  atClientPreference.isLocalStoreRequired = true;
  atClientPreference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
  return atClientPreference;
}
