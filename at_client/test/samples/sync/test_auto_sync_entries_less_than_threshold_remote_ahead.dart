import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';

import '../test_util.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atSign, 'wavi', TestUtil.getAlicePreference());
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  for (var i = 0; i < 2; i++) {
    var phoneKey = AtKey()..key = 'ph_$i';
    var value = '$i';
    var result = await atClient.put(phoneKey, value);
    print(result);
  }
  // execute remote update command from ssl terminal
}
