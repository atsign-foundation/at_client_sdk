import 'package:at_client/at_client.dart';
import 'test_util.dart';
import 'package:at_commons/at_commons.dart';

void main() async {
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getAlicePreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
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
