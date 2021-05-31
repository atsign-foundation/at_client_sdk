import 'dart:io';

import 'package:at_client/src/client/at_client_impl.dart';

import 'test_util.dart';

void main() async {
  try {
    var atSign = '@alice🛠';
    await AtClientImpl.createClient(
        atSign, 'me', TestUtil.getAlicePreference());
    var atClient = await AtClientImpl.getClient(atSign);
    var result = await atClient.getSyncManager().isInSync();
    print('is in sync:$result');
    await atClient.getSyncManager().sync();
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
