import 'package:at_client/at_client.dart';

import '../test_util.dart';
import '../../test_utils/hive_store.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: TestUtil.getAlicePreference(),
        storage: hiveStoreFor(atSign, TestUtil.getAlicePreference())));
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  for (var i = 0; i < 5; i++) {
    var phoneKey = AtKey()..key = 'phone_$i';
    var value = '$i';
    var result = await atClient.put(phoneKey, value);
    print(result);
  }
}
