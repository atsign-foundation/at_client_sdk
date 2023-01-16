import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

late AtClientManager atClientManager;
late String currentAtSign;
late String sharedWithAtSign;

Future<void> setUpMethod() async {
  currentAtSign = '@alice🛠';
  sharedWithAtSign = '@bob🛠';
  var preference = TestUtils.getPreference(currentAtSign);
  atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(currentAtSign, 'me', preference);
  atClientManager.atClient.syncService.sync();
  // To setup encryption keys
  await setEncryptionKeys(currentAtSign, preference);
}

void main() {
  setUp(() async {
    await setUpMethod();
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
  tearDown(() async => await tearDownMethod());
}

Future<void> tearDownMethod() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
