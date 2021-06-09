import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';
import 'package:at_commons/at_commons.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice🛠', 'me', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient('@alice🛠'));
    if(atClient == null) {
      print('unable to create at client instance');
      return;
    }
    //llookup:phone.me@alice🛠
    var atKey = AtKey()..key = 'phone';
    var alicePhone = await atClient.get(atKey);
    print(alicePhone.value);
    //llookup:alice🛠:phone.me@alice🛠
//    var privatePhoneKey = AtKey()
//      ..key = 'phone'
//      ..sharedWith = '@alice🛠';
//    var alicePrivatePhone = await atClient.get(privatePhoneKey);
//    print(alicePrivatePhone.value);
    //llookup:public:phone.me@alice🛠
    var metadata = Metadata()..isPublic = true;
    var publicPhoneKey = AtKey()
      ..key = 'phone'
      ..metadata = metadata;
    var alicePublicPhone = await atClient.get(publicPhoneKey);
    print(alicePublicPhone.value);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
