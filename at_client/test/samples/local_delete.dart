import 'package:at_client/at_client.dart';
import 'test_util.dart';
import 'package:at_commons/at_commons.dart';

void main() async {
  final atsign = '@alice🛠';
  final preference = TestUtil.getAlicePreference();
  var atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atsign, 'wavi', preference);
  var atClient = atClientManager.atClient;
  var atKey = AtKey()
    ..key = 'phone'
    ..sharedWith = '@alice🛠';
  var result = await atClient.delete(atKey);
  print(result);
}
