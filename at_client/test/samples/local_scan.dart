import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@murali', 'me', TestUtil.getAlicePreference());
    var atClient = await AtClientImpl.getClient('@murali');
    var result = await atClient.getKeys();
    result.forEach((key) {
      print(key.toString());
    });
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
