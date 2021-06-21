import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/stream/at_stream_request.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/stream.dart';

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
    Function dummyFunction = () {};
    var monitorPreference = MonitorPreference();
    await atClient.startMonitor(
        dummyFunction, dummyFunction, monitorPreference);
    var stream = atClient.createStream(StreamType.SEND);
    var atStreamRequest =
        AtStreamRequest('@bob🛠', 'cat.jpeg', _onDone, _onError);
    atStreamRequest.namespace = 'atmosphere';
    await stream.sender!.send(atStreamRequest);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}

void _onDone(AtStreamResponse response) {
  print('stream done callback');
  print(response);
}

void _onError(AtStreamResponse response) {
  print('stream error callback');
  print(response);
}
