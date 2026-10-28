import 'package:at_client/at_client.dart';
import 'test_util.dart';
import '../test_utils/hive_store.dart';

void main() async {
  final atsign = '@alice🛠';
  final preference = TestUtil.getAlicePreference();
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atsign,
        namespace: 'wavi',
        preference: preference,
        storage: hiveStoreFor(atsign, preference)));
  var atClient = atClientManager.atClient;
  var atKey = AtKey()
    ..key = 'phone'
    ..sharedWith = '@alice🛠';
  var result = await atClient.delete(atKey);
  print(result);
}
