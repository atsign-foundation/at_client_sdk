import 'dart:io';
import 'package:at_client/at_client.dart';
import 'test_util.dart';

void main() async {
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getPreferenceRemote();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    var stats_result = await atClient
        .getRemoteSecondary()!
        .executeCommand('stats\n', auth: true);
    print(stats_result);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
