import 'dart:async';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/response/stream_notification_response_parser.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/at_stream_ack.dart';

import 'test_util.dart';

AtClientImpl? atClient;

void main() async {
  try {
    var preference = TestUtil.getBobPreference();
    await AtClientImpl.createClient('@bob🛠', 'me', preference);
    atClient = await AtClientImpl.getClient('@bob🛠') as AtClientImpl;
    //var monitorPreference = MonitorPreference()..regex = 'atmosphere';
    //monitorPreference.keepAlive = true;
    //await atClient!.startMonitor(
    //   _notificationCallBack, _monitorErrorCallBack, monitorPreference);
    await atClient!.startMonitor(preference.privateKey!, _notificationCallBack,
        regex: 'atmosphere');
    while (true) {
      print('Waiting for notification');
      await Future.delayed(Duration(seconds: 5));
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void _monitorErrorCallBack(var error) {
  print('error in monitor callback $error');
}

Future<void> _notificationCallBack(var response) async {
  print('In receiver _notificationCallBack : $response');
  final streamNotification =
      StreamNotificationParser('atmosphere').parseStreamNotification(response);
  if (streamNotification != null) {
    var userResponse = true; //UI user response
    if (userResponse == true) {
      print('user accepted transfer.Sending ack back');
      final atStream = atClient!.createStream(StreamType.RECEIVE,
          streamId: streamNotification.streamId);

      await atStream.receiver!.ack(
          AtStreamAck()
            ..senderAtSign = streamNotification.senderAtSign
            ..fileName = streamNotification.fileName
            ..fileLength = streamNotification.fileLength,
          _streamCompletionCallBack,
          _streamProgressCallBack);
    }
  } else {
    NotificationResponseParser().parse(response);
  }
}

void _streamProgressCallBack(var bytesReceived) {
  print('Receive callback bytes received: $bytesReceived');
}

Future<void> _streamCompletionCallBack(var streamId) async {
  print('Transfer done for stream: $streamId');
  //sleep(Duration(seconds: 1));
//  var atCommand = 'stream:resume@murali namespace:atmosphere startByte:3 $streamId test1.txt 15\n';
//  print('In _streamCompletionCallBack atCommand : ${atCommand}');
//  await atClient!.getRemoteSecondary()!.executeCommand(atCommand);
}

void streamResumeTest(String streamId, int startByte) {
// Step:1 Let the sender know of the request

// stream:resume:<stream-id>
// step 2 : Sender should send ack
// step 3 : get bytes from the startByte
}
