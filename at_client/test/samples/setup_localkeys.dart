import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_demo_data/at_demo_data.dart' as at_demos;
import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getAlicePreference();
    var atsign = '@alice🛠';
    //1.
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    var metadata = Metadata();
    metadata.namespaceAware = false;
    var result;
    // set pkam private key
    result = await atClient.getLocalSecondary().putValue(
        AT_PKAM_PRIVATE_KEY, at_demos.pkamPrivateKeyMap[atsign]); // set pkam public key
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PUBLIC_KEY, at_demos.pkamPublicKeyMap[atsign]);
    // set encryption private key
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_ENCRYPTION_PRIVATE_KEY, at_demos.encryptionPrivateKeyMap[atsign]);

    // set encryption public key. should be synced
    metadata.isPublic = true;
    var atKey = AtKey()
      ..key = 'publickey'
      ..metadata = metadata;
    result = await atClient.put(atKey, at_demos.encryptionPublicKeyMap[atsign]);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
