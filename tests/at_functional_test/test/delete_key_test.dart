import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  late AtClientManager atClientManager;
  late AtClient atClient;
  var currentAtSign = '@alice🛠';
  var namespace = 'wavi';
  setUpAll(() async {
    var preference = getPreference(currentAtSign);
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace, preference);
    atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(currentAtSign, preference);
  });

  group('A group of tests related to deletion of a key', () {
    test(
        'A test to verify the deletion of a local key - create a local key using a static factory method',
            () async {
          var localKey = AtKey.local('local-key', currentAtSign).build();
          // Create local key
          var putResponse = await atClient.put(localKey, 'dummy-local-value');
          expect(putResponse, true);
          // Fetch the key
          AtValue getResponse = await atClient.get(localKey);
          expect(getResponse.value, 'dummy-local-value');
          // Delete the key
          var deleteResponse = await atClient.delete(localKey);
          expect(deleteResponse, true);
          // Verify key is deleted
          var isLocalKeyExist = atClient
              .getLocalSecondary()
              ?.keyStore
              ?.isKeyExists(localKey.toString());
          expect(isLocalKeyExist, false);
        });

    test(
        'A test to verify the deletion of a local key - create a local key setting isLocal to true',
            () async {
          var localKey = AtKey()
            ..key = 'local-key'
            ..isLocal = true
            ..sharedBy = currentAtSign;
          // Create local key
          var putResponse = await atClient.put(localKey, 'dummy-local-value');
          expect(putResponse, true);
          // Fetch the key
          AtValue getResponse = await atClient.get(localKey);
          expect(getResponse.value, 'dummy-local-value');
          // Delete the key
          var deleteResponse = await atClient.delete(localKey);
          expect(deleteResponse, true);
          // Verify key is deleted
          var isLocalKeyExist = atClient
              .getLocalSecondary()
              ?.keyStore
              ?.isKeyExists(localKey.toString());
          expect(isLocalKeyExist, false);
        });
  });
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

AtClientPreference getPreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  preference.syncRegex = 'wavi';
  return preference;
}