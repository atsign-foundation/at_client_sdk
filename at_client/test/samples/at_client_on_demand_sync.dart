import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    var preference = TestUtil.getPreferenceLocal();
    await AtClientImpl.createClient('@alice', 'me', preference);
    var atClient = await AtClientImpl.getClient('@alice');
    await atClient.getSyncManager().sync();
    var result = await atClient.getSyncManager().isInSync();
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
