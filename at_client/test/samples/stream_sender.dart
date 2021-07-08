import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';

import 'test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice🛠', 'me', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient('@alice🛠'));
    if (atClient == null) {
      print('unable to create at client instance');
      return;
    }
    Function dummyFunction = (){};
    var monitorPreference = MonitorPreference();
    await atClient.startMonitor(dummyFunction, dummyFunction, monitorPreference);
    var streamResult =
        await atClient.stream('@bob🛠', 'cat.jpeg', namespace: 'atmosphere');
    print(streamResult);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
