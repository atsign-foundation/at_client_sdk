import 'package:at_client/at_client.dart';
import 'test_util.dart';

void main() async {
  final atsign = '@alice🛠';
  final preference = TestUtil.getAlicePreference();
  var atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atsign, 'wavi', preference);
  var atClient = atClientManager.atClient;
  var atKey = AtKey()..key = 'testkey12';
  var value = '123';
  var metadata = Metadata()..isPublic = true;
  atKey.metadata = metadata;
  var result = await atClient.put(atKey, value);
  print(result);
}
