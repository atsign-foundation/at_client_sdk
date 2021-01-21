import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    var atSign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    await AtClientImpl.createClient(
        atSign, 'me', TestUtil.getAlicePreference());
    var atClient = await AtClientImpl.getClient(atSign);
    await atClient.getSyncManager().init(atSign, preference, atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    var result = await atClient.getSyncManager().isInSync();
    print(result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
