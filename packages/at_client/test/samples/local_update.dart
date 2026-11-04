import 'package:at_client/at_client_io.dart';

import 'test_util.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/no_keys.dart';
import '../test_utils/transport.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: TestUtil.getAlicePreference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(TestUtil.getAlicePreference()),
        atKeysIo: noKeysFor(atSign),
        storage: hiveStoreFor(atSign, TestUtil.getAlicePreference())));
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  var phoneKey = AtKey()..key = 'phone';
  var value = '+1 100 200 300';

  var result = await atClient.put(phoneKey, value);
  print(result);

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
