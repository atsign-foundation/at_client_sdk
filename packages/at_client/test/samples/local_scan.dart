import 'package:at_client/at_client_io.dart';

import 'test_util.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/no_keys.dart';
import '../test_utils/transport.dart';

void main() async {
  try {
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

    var result = await atClientManager.atClient.getKeys();
    for (var key in result) {
      print(key.toString());
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
