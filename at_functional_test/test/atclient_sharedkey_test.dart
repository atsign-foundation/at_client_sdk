import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  late AtClientManager atClientManager;
  late AtClient atClient;
  var sharedWithAtSign = '@bob🛠';
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

  test('shared key - check sharedKey and checksum in metadata', () async {
    var phoneKey = AtKey()
      ..key = 'location'
      ..sharedWith = sharedWithAtSign;
    var value = 'NewJersey';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var metadata = await atClient.getMeta(phoneKey);
    expect(metadata!.sharedKeyEnc, isNotEmpty);
    expect(metadata.pubKeyCS, isNotEmpty);
  });

  test('sharedKey and checksum metadata sync to local storage', () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = (Metadata()..ttl = 120000);
    var value = '+91 887 888 3435';
    var encryptionService =
        AtKeyEncryptionManager().get(phoneKey, currentAtSign);
    var encryptedValue = await encryptionService.encrypt(phoneKey, value);
    var result = await atClient.getRemoteSecondary()!.executeCommand(
        'update:sharedKeyEnc:${phoneKey.metadata?.sharedKeyEnc}:pubKeyCS:${phoneKey.metadata?.pubKeyCS}:${phoneKey.sharedWith}:${phoneKey.key}.$namespace$currentAtSign $encryptedValue\n',
        auth: true);
    expect(result != null, true);
    var isSyncInProgress = true;
    atClientManager.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    var metadata = await atClient.getMeta(phoneKey);
    expect(metadata?.sharedKeyEnc, isNotEmpty);
    expect(metadata?.pubKeyCS, isNotEmpty);
  }, timeout: Timeout(Duration(minutes: 3)));
}

AtClientPreference getPreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
