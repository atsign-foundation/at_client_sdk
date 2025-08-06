import 'package:at_client/src/manager/at_client_manager.dart';

import 'test_util.dart';

void main() async {
  try {
    final atSign = '@alice🛠';
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtil.getAlicePreference());

    var result = await atClientManager.atClient.getKeys();
    for (var key in result) {
      print(key.toString());
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
