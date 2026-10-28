import 'dart:io';

import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getAlicePreference();
    var atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: atsign, namespace: 'wavi', preference: preference));
    var atClient = atClientManager.atClient;
    // auth scan
    var authScanResult = await atClient
        .getRemoteSecondary()!
        .executeCommand('scan\n', auth: true);
    print(authScanResult);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
