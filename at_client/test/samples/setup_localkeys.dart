import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';

import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getAlicePreference();
    var atsign = '@alice';
    //1.
    await AtClientImpl.createClient('@alice', 'me', preference);
    var atClient = await AtClientImpl.getClient('@alice');
    await atClient.getSyncManager().init(atsign, preference,
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    var metadata = Metadata();
    metadata.namespaceAware = false;
    var result;
    // set pkam private key
    result = await atClient.getLocalSecondary().putValue(
        AT_PKAM_PRIVATE_KEY, '<your_pkam_private_key>'); // set pkam public key
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_PKAM_PUBLIC_KEY, '<your_pkam_public_key>');
    // set encryption private key
    result = await atClient
        .getLocalSecondary()
        .putValue(AT_ENCRYPTION_PRIVATE_KEY, '<your_encryption_private_key>');

    // set encryption public key. should be synced
    metadata.isPublic = true;
    var atKey = AtKey()
      ..key = 'publickey'
      ..metadata = metadata;
    result = await atClient.put(atKey, '<your_encryption_public_key>');
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
