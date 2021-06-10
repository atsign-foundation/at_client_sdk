import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';
import 'package:at_commons/at_commons.dart';

void main() async {
  await AtClientImpl.createClient(
      '@alice🛠', 'me', TestUtil.getAlicePreference());
  var atClient = await (AtClientImpl.getClient('@alice🛠'));
  if(atClient == null) {
    print('unable to create at client instance');
    return;
  }
  var atKey = AtKey()..key = 'testkey12';
  var value = '123';
  var metadata = Metadata()..isPublic = true;
  atKey.metadata = metadata;
  var result = await atClient.put(atKey, value);
  print(result);
}
