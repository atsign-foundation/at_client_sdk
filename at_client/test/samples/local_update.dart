import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';
import 'package:at_commons/at_commons.dart';

void main() async {
  await AtClientImpl.createClient(
      '@alice🛠', 'me', TestUtil.getAlicePreference());
  var atClient = await AtClientImpl.getClient('@alice🛠');
  // phone.me@alice🛠
  var phoneKey = AtKey()..key = 'phone';
  var value = '+1 100 200 300';
  var result = await atClient.put(phoneKey, value);
  print(result);
  // @alice:phone.me@alice🛠
  var privatePhoneKey = AtKey()
    ..key = 'phone'
    ..sharedWith = '@alice🛠';
  var privatePhoneValue = '+1 100 200 301';
  var updatePrivatePhoneResult =
      await atClient.put(privatePhoneKey, privatePhoneValue);
  print(updatePrivatePhoneResult);

  // public:phone.me@alice🛠
  var metadata = Metadata()..isPublic = true;
  var publicPhoneKey = AtKey()
    ..key = 'phone'
    ..metadata = metadata;
  var publicPhoneValue = '+1 100 200 302';
  var updatePublicPhoneResult =
      await atClient.put(publicPhoneKey, publicPhoneValue);
  print(updatePublicPhoneResult);
}
