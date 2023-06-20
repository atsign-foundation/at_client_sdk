import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  String currentAtSign = '@alice🛠';
  String sharedWithAtSign = '@bob🛠';

  setUpAll(() async {
    var preference = TestUtils.getPreference(currentAtSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, 'me', preference);
    // To setup encryption keys
    await AtEncryptionKeysLoader.getInstance()
        .setEncryptionKeys(atClientManager.atClient, currentAtSign);
  });

  test(
      'A test to verify deletion of key when overriding the namespace in atKey',
      () async {
    // The namespace in the preference is "me". Overriding the namespace in the atKey to "wavi"
    AtKey atKey = (AtKey.shared('keyNamespaceOverriding',
            namespace: 'wavi', sharedBy: currentAtSign)
          ..sharedWith(sharedWithAtSign))
        .build();
    await atClientManager.atClient.put(atKey, 'dummy_value');
    expect(
        atClientManager.atClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        true);

    // Delete the key
    await atClientManager.atClient.delete(atKey);
    expect(
        atClientManager.atClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        false);
  });
}
