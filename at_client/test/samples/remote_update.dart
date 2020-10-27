import 'package:at_client/at_client.dart';
import 'test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient('@alice', null, TestUtil.getPreferenceRemote());
    var atClient = await AtClientImpl.getClient('@alice');
    var result = await atClient
        .getRemoteSecondary()
        .executeCommand('update:location@alice india\n', auth: true);
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
