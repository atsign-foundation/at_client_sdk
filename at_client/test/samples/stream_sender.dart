import 'dart:io';

import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getAlicePreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    var streamResult =
        await atClient.stream('@bob🛠', 'cat.jpeg', namespace: 'atmosphere');
    print(streamResult);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
