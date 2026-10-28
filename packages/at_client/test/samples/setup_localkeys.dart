import 'package:at_client/at_client.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_demo_data/at_demo_data.dart' as at_demos;

import 'test_util.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/no_keys.dart';

void main() async {
  try {
    final atSign = '@alice🛠';
    var atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: atSign,
          namespace: 'wavi',
          preference: TestUtil.getAlicePreference(),
          atKeysIo: noKeysFor(atSign),
          storage: hiveStoreFor(atSign, TestUtil.getAlicePreference())));
    final atClient = atClientManager.atClient;
    var metadata = Metadata();
    metadata.namespaceAware = false;
    bool result;
    // set pkam private key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atPkamPrivateKey,
        at_demos.pkamPrivateKeyMap[atSign]!); // set pkam public key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atPkamPublicKey, at_demos.pkamPublicKeyMap[atSign]!);
    // set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
        AtConstants.atEncryptionPrivateKey,
        at_demos.encryptionPrivateKeyMap[atSign]!);
    result = await atClient
        .getLocalSecondary()!
        .putValue(AtConstants.atEncryptionSelfKey, at_demos.aesKeyMap[atSign]!);
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
