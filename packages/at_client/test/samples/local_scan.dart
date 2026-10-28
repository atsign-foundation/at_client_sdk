import 'package:at_client/at_client.dart';

import 'test_util.dart';
import '../test_utils/hive_store.dart';

void main() async {
  try {
    final atSign = '@alice🛠';
    var atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: atSign,
          namespace: 'wavi',
          preference: TestUtil.getAlicePreference(),
          storage: hiveStoreFor(atSign, TestUtil.getAlicePreference())));

    var result = await atClientManager.atClient.getKeys();
    for (var key in result) {
      print(key.toString());
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
