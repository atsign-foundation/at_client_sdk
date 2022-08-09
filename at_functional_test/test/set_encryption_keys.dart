import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';

import 'at_demo_credentials.dart' as demo_credentials;

Future<void> setEncryptionKeys(
    String atsign, AtClientPreference atClientPreference) async {
  try {
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', atClientPreference);
    var atClient = atClientManager.atClient;
    var metadata = Metadata();
    metadata.namespaceAware = false;
    bool result;

    //Set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
        AT_ENCRYPTION_PRIVATE_KEY,
        demo_credentials.encryptionPrivateKeyMap[atsign]!);
    print('Setting encryption private key: $result');

    // set encryption public key. should be synced
    // set encryption public key. should be synced
    var encryptionPublicKey = '$AT_ENCRYPTION_PUBLIC_KEY$atsign';
    result = await atClient
        .getLocalSecondary()!.putValue(
        encryptionPublicKey,
        demo_credentials.encryptionPublicKeyMap[atsign]!);
    print('Setting encryption public key: $result');

    // set self encryption key
    await atClient
        .getLocalSecondary()!
        .putValue(AT_ENCRYPTION_SELF_KEY, demo_credentials.aesKeyMap[atsign]!);
    print('Setting self encryption key: $result');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
