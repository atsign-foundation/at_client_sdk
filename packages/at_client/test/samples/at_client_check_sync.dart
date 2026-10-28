import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    AtSignLogger.root_level = 'finer';
    var atSign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    var atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: atSign, namespace: 'wavi', preference: preference));
    var result = await atClientManager.atClient.syncService.isInSync();
    print('is in sync? $result');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
