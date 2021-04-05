import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'test_util.dart';
import 'package:at_demo_data/src/at_demo_credentials.dart' as at_demo;

void main() async {
  try {
    var preference = TestUtil.getBobPreference();
    var atsign = '@bob🛠';
    //1.
    await AtClientImpl.createClient(atsign, 'atmosphere', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    await atClient.getSyncManager().init(atsign, preference,
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    var metadata = Metadata();
    metadata.namespaceAware = false;
    var result;
    // set pkam private key
    result = await atClient.getLocalSecondary().putValue(AT_PKAM_PRIVATE_KEY,
        at_demo.pkamPrivateKeyMap[atsign]); // set pkam public key
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PUBLIC_KEY, at_demo.pkamPublicKeyMap[atsign]);
    // set encryption private key
    result = await atClient.getLocalSecondary().putValue(
        AT_ENCRYPTION_PRIVATE_KEY, at_demo.encryptionPrivateKeyMap[atsign]);

    result = await atClient
        .getLocalSecondary()
        .putValue(AT_ENCRYPTION_SELF_KEY, at_demo.aesKeyMap[atsign]);
    // set encryption public key. should be synced

    metadata.isPublic = true;
    var atKey = AtKey()
      ..key = 'publickey'
      ..metadata = metadata;
    result = await atClient.put(atKey, at_demo.encryptionPublicKeyMap[atsign]);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
