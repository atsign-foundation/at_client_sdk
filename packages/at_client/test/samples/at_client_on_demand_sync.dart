import 'dart:io';
import 'package:at_client/at_client.dart';

import 'test_util.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/no_keys.dart';

void main() async {
  try {
    AtSignLogger.root_level = 'finer';
    var atSign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    var atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: atSign,
          namespace: 'wavi',
          preference: preference,
          atKeysIo: noKeysFor(atSign),
          storage: hiveStoreFor(atSign, preference)));
    atClientManager.atClient.syncService.sync();
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
