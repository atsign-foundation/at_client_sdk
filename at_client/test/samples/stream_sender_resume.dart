import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/stream/at_stream_request.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/at_stream.dart';

import 'test_util.dart';

AtClient? atClient;
void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice🛠', 'me', TestUtil.getAlicePreference());
    atClient = await (AtClientImpl.getClient('@alice🛠'));
    if (atClient == null) {
      print('unable to create at client instance');
      return;
    }
    Function dummyFunction = () {};
    var monitorPreference = MonitorPreference();
    await atClient!
        .startMonitor(_notificationCallback, dummyFunction, monitorPreference);
    var stream = atClient!.createStream(
      StreamType.SEND,
    );
    print('sender : ${stream.sender} receiver : ${stream.receiver}');
    var atStreamRequest =
        AtStreamRequest('@bob🛠', '/home/murali/Pictures/@/cat.jpeg');
    atStreamRequest.namespace = 'atmosphere';
    while (true) {
      print('Waiting for notification');
      await Future.delayed(Duration(seconds: 5));
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void _onDone(AtStreamResponse response) {
  print('stream done callback');
  print(response);
}

void _onError(AtStreamResponse response) {
  print('stream error callback');
  print(response);
}

Future<void> _notificationCallback(var response) async {
  print('stream resume notification received $response');
  response = response.replaceFirst('notification:', '');
  var responseJson = jsonDecode(response);
  var notificationKey = responseJson['key'].toString();
  notificationKey = notificationKey.replaceFirst('null', '');
  notificationKey = notificationKey.replaceFirst('stream_resume ', '');
  var fromAtSign = responseJson['from'];
  print(notificationKey);
  var streamId = notificationKey.split(':')[1];
  var startByte = int.parse(notificationKey.split(':')[2]);
  var stream = atClient!.createStream(StreamType.SEND, streamId: streamId);
  print(
      'sender : ${stream.sender} receiver : ${stream.receiver} streamId:$streamId startByte: $startByte');
  var atStreamRequest = AtStreamRequest('@bob🛠', 'cat.jpeg');
  atStreamRequest.namespace = 'atmosphere';
  atStreamRequest.startByte = startByte;
  await stream.sender!.send(atStreamRequest, _onDone, _onError);
}
