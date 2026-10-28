import 'package:at_client/at_client.dart';

import '../test_util.dart';
import '../../test_utils/hive_store.dart';
import '../../test_utils/no_keys.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: TestUtil.getAlicePreference(),
        atKeysIo: noKeysFor(atSign),
        storage: hiveStoreFor(atSign, TestUtil.getAlicePreference())));
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  for (var i = 0; i < 2; i++) {
    var phoneKey = AtKey()..key = 'ph_$i';
    var value = '$i';
    var result = await atClient.put(phoneKey, value);
    print(result);
  }
  // execute remote update command from ssl terminal
}
