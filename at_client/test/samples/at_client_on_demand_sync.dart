import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';

import 'test_util.dart';

void main() async {
  try {
    var atSign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    await AtClientImpl.createClient(
        atSign, 'me', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient(atSign));
    if (atClient == null) {
      print('unable to create at client instance');
      return;
    }
    var result = await atClient.getSyncManager().isInSync();
    print('is in sync:$result');
    await atClient.getSyncManager().sync();
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
