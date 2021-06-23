import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';

import 'test_util.dart';

void main() async {
  try {
    var atSign = '@alice🛠';
    await AtClientImpl.createClient(
        atSign, 'me', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient(atSign));
    if(atClient == null) {
      print('unable to create at client instance');
      return;
    }
    var result = await atClient.getSyncManager()!.isInSync();
    print('is in sync:$result');
    await atClient.getSyncManager()!.sync(_onSyncDone);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  await Future.delayed(Duration(seconds: 10));
}

void _onSyncDone(var syncManager){
  print('sync done');
}
