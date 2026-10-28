import 'package:at_client/at_client_io.dart';
import 'test_util.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/no_keys.dart';
import '../test_utils/transport.dart';

void main() async {
  final atsign = '@alice🛠';
  final preference = TestUtil.getAlicePreference();
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atsign,
        namespace: 'wavi',
        preference: preference,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(preference),
        atKeysIo: noKeysFor(atsign),
        storage: hiveStoreFor(atsign, preference)));
  var atClient = atClientManager.atClient;
  var atKey = AtKey()
    ..key = 'phone'
    ..sharedWith = '@alice🛠';
  var result = await atClient.delete(atKey);
  print(result);
}
