import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  test('shared key - check sharedKey and checksum in metadata', () async {
    var atsign = '@alice🛠';
    var preference = getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // @bob🛠:location.wavi@alice🛠
    var phoneKey = AtKey()
      ..key = 'location'
      ..sharedWith = '@bob🛠';
    var value = 'NewJersey';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var metadata = await atClient.getMeta(phoneKey);
    expect(metadata!.sharedKeyEnc, isNotEmpty);
    expect(metadata.pubKeyCS, isNotEmpty);
  });
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
