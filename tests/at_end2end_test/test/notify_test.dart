import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() async {
  late AtClientManager currentAtClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = TestConstants.namespace;

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace, authType);
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
    expect(notificationListJson[0]['value'] != value,
        true); //encrypted value should be different from actual value
  });
  test('Notify a key with value by setting encryptValue to false', () async {
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
        .notify(NotificationParams.forUpdate(phoneKey, value: value),
            encryptValue: false);
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
    expect(notificationListJson[0]['isEncrypted'], 'false');
    expect(notificationListJson[0]['value'], value);
  });
}
