import 'package:at_client/at_client.dart';
import 'test_util.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/no_keys.dart';

void main() async {
  final atsign = '@alice🛠';
  final preference = TestUtil.getAlicePreference();
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atsign,
        namespace: 'wavi',
        preference: preference,
        atKeysIo: noKeysFor(atsign),
        storage: hiveStoreFor(atsign, preference)));
  var atClient = atClientManager.atClient;
  var atKey = AtKey()..key = 'testkey12';
  var value = '123';
  var metadata = Metadata()..isPublic = true;
  atKey.metadata = metadata;
  var result = await atClient.put(atKey, value);
  print(result);
}
