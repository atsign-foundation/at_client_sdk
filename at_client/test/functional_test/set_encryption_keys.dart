import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';

import 'at_demo_credentials.dart' as demo_credentials;

Future<void> setEncryptionKeys(
    String atsign, AtClientPreference atClientPreference) async {
  try {
    await AtClientImpl.createClient(atsign, 'me', atClientPreference);
    var atClient = await AtClientImpl.getClient(atsign);
    var metadata = Metadata();
    metadata.namespaceAware = false;
    var result;

    //Set encryption private key
    result = await atClient.getLocalSecondary().putValue(
        AT_ENCRYPTION_PRIVATE_KEY,
        demo_credentials.encryptionPrivateKeyMap[atsign]);

    // set encryption public key. should be synced
    metadata.isPublic = true;
    var atKey = AtKey()
      ..key = 'publickey'
      ..metadata = metadata;
    result = await atClient.put(
        atKey, demo_credentials.encryptionPublicKeyMap[atsign]);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
