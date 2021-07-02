import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/at_stream_ack.dart';

import 'test_util.dart';

AtClient? atClient;

void main() async {
  try {
    await AtClientImpl.createClient(
        '@bob🛠', 'me', TestUtil.getBobPreference());
    atClient = await AtClientImpl.getClient('@bob🛠');
    var monitorPreference = MonitorPreference()..regex = 'atmosphere';
    await atClient!.startMonitor(
        _notificationCallBack, _monitorErrorCallBack, monitorPreference);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void _monitorErrorCallBack(var error) {
  print('error in monitor callback $error');
}

Future<void> _notificationCallBack(var response) async {
  response = response.replaceFirst('notification:', '');
  var responseJson = jsonDecode(response);
  var notificationKey = responseJson['key'];
  var fromAtSign = responseJson['from'];
  var atKey = notificationKey.split(':')[1];
  atKey = atKey.replaceFirst(fromAtSign, '');
  atKey = atKey.trim();
  if (atKey == 'stream_id.atmosphere') {
    var valueObject = responseJson['value'];
    var streamId = valueObject.split(':')[0];
    var fileName = valueObject.split(':')[1];
    var fileLength = int.parse(valueObject.split(':')[2]);
    fileName = utf8.decode(base64.decode(fileName));
    var userResponse = true; //UI user response
    if (userResponse == true) {
      print('user accepted transfer.Sending ack back');
      final atStream =
          atClient!.createStream(StreamType.RECEIVE, streamId: streamId);
      ;
      await atStream.receiver!.ack(
          AtStreamAck()
            ..senderAtSign = fromAtSign
            ..fileName = fileName
            ..fileLength = fileLength,
          _streamCompletionCallBack,
          _streamProgressCallBack);
    }
  } else {
    //TODO handle other notifications
    print('some other notification');
    print(response);
  }
}

void _streamProgressCallBack(var bytesReceived) {
  print('Receive callback bytes received: $bytesReceived');
}

void _streamCompletionCallBack(var streamId) {
  print('Transfer done for stream: $streamId');
}
