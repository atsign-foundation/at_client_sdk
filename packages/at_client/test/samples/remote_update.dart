import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'test_util.dart';

void main() async {
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getPreferenceRemote();
    var atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        atsign, 'wavi', preference,
        storage: InMemoryAtClientStorage(atSign: atsign));
    var atClient = atClientManager.atClient;
    var result = await atClient
        .getRemoteSecondary()!
        .executeCommand('update:location@alice india\n', auth: true);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
