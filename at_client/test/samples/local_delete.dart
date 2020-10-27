import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';
import 'package:at_commons/at_commons.dart';

void main() async {
  await AtClientImpl.createClient(
      '@alice🛠', 'me', TestUtil.getAlicePreference());
  var atClient = await AtClientImpl.getClient('@alice🛠');
  var atKey = AtKey()
    ..key = 'phone'
    ..sharedWith = '@alice🛠';
  var result = await atClient.delete(atKey);
  print(result);
}
