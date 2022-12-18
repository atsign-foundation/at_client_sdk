import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

late AtClientManager currentAtClientManager;
late String currentAtSign;
late String sharedWithAtSign;
final namespace = 'wavi';

void main() {
  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
  });

  test(
      'A test to verify deletion of key when overriding the namespace in atKey',
      () async {
    // The namespace in the preference is "wavi". Overriding the namespace in the atKey to "buzz"
    var atKey = (AtKey.shared('keyNamespaceOverriding',
            namespace: 'buzz', sharedBy: currentAtSign)
          ..sharedWith(sharedWithAtSign))
        .build();
    await currentAtClientManager.atClient.put(atKey, 'dummy_value');
    expect(
        currentAtClientManager.atClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        true);

    // Delete the key
    await currentAtClientManager.atClient.delete(atKey);
    expect(
        currentAtClientManager.atClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        false);
  });
}
