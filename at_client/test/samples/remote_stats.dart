import 'dart:io';
import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice', null, TestUtil.getPreferenceRemote());
    var atClient = await AtClientImpl.getClient('@alice');
    var stats_result = await atClient
        .getRemoteSecondary()
        .executeCommand('stats\n', auth: true);
    print(stats_result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
