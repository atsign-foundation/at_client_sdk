import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_demo_data/at_demo_data.dart' as at_demos;

import 'test_util.dart';

void main() async {
  try {
    final atSign = '@alice🛠';
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtil.getAlicePreference());
    final atClient = atClientManager.atClient;
    var metadata = Metadata();
    metadata.namespaceAware = false;
    bool result;
    // set pkam private key
    result = await atClient.getLocalSecondary().putValue(AT_PKAM_PRIVATE_KEY,
        at_demos.pkamPrivateKeyMap[atSign]!); // set pkam public key
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PUBLIC_KEY, at_demos.pkamPublicKeyMap[atSign]!);
    // set encryption private key
    result = await atClient.getLocalSecondary().putValue(
        AT_ENCRYPTION_PRIVATE_KEY, at_demos.encryptionPrivateKeyMap[atSign]!);
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_ENCRYPTION_SELF_KEY, at_demos.aesKeyMap[atSign]!);
    // set encryption public key. should be synced
    metadata.isPublic = true;
    var atKey = AtKey()
      ..key = 'publickey'
      ..metadata = metadata;
    result =
        await atClient.put(atKey, at_demos.encryptionPublicKeyMap[atSign]!);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
