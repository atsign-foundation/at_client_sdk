import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';
import 'test_util.dart';
import 'package:crypton/crypton.dart';

void main() async {
//  var atClient =
//  await AtClientImpl.getClient('@jagan', 'me', TestUtil.getJaganPreference());
//  var result = await atClient.getRemoteSecondary().executeCommand('notify:@naresh:stream_init@jagan:123\n',auth: true);
//  print(result);
  var rsaKeypair = RSAKeypair.fromRandom();
  var publicKey = rsaKeypair.privateKey.toString();
  print('public key: ${publicKey}');
}
