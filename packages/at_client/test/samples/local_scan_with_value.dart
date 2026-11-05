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
    final atClient = atClientManager.atClient;
    // Option 1. Get string keys and convert to AtKey
    var result = await atClient.getKeys();
    for (var key in result) {
      var atKey = AtKey.fromString(key);
      var value = await atClient.get(atKey);
      print('$key --> ${value.value}');
    }

    // Option 2. Get AtKeys
    var atKeys = await atClient.getAtKeys();
    for (var key in atKeys) {
      var value = await atClient.get(key);
      print('$key --> ${value.value}');
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void process() {}
