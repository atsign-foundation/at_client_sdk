import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/stream_notification_parser.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/at_stream_ack.dart';
import 'package:at_utils/at_logger.dart';
import 'test_util.dart';

var atClient;

void main() async {
  AtSignLogger.root_level = 'finer';
  try {
    final atsign = '@bob🛠';
    final preference = TestUtil.getBobPreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    atClientManager.notificationService
        .subscribe(regex: 'atmosphere')
        .listen((notification) {
      _notificationCallBack(notification);
    });
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

Future<void> _notificationCallBack(AtNotification atNotification) async {
  var notificationKey = atNotification.key;
  var fromAtSign = atNotification.from;
  var atKey = notificationKey.split(':')[1];
  atKey = atKey.replaceFirst(fromAtSign, '');
  atKey = atKey.trim();
  if (atKey == 'stream_id.atmosphere') {
    final streamNotification = StreamNotificationParser('atmosphere')
        .parseStreamNotification(atNotification);
    if (streamNotification == null) {
      return;
    }
    var userResponse = true; //UI user response
    if (userResponse == true) {
      print('user accepted transfer.Sending ack back');
      final atStream = AtClientManager.getInstance().streamService.createStream(
          StreamType.RECEIVE,
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
    //TODO handle other notifications
    print('some other notification');
    print(atNotification);
  }
}

void _streamProgressCallBack(var bytesReceived) {
  print('Receive callback bytes received: $bytesReceived');
}

void _streamCompletionCallBack(var streamId) {
  print('Transfer done for stream: $streamId');
}
