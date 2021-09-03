import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

import 'test_util.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atSign, 'wavi', TestUtil.getAlicePreference());
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  var phoneKey = AtKey()..key = 'phone';
  var value = '+1 100 200 300';

  var result = await atClient.put(phoneKey, value);
  print(result);

  // public:phone.me@alice🛠
  var metadata = Metadata()..isPublic = true;
  var publicPhoneKey = AtKey()
    ..key = 'phone'
    ..metadata = metadata;
  var publicPhoneValue = '+1 100 200 302';
  var updatePublicPhoneResult =
      await atClient.put(publicPhoneKey, publicPhoneValue);
  print(updatePublicPhoneResult);
}
