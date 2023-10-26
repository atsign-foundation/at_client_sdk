import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  String currentAtSign = '@alice🛠';
  String sharedWithAtSign = '@bob🛠';

  setUpAll(() async {
    atClientManager = await TestUtils.initAtClient(currentAtSign, 'wavi');
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
