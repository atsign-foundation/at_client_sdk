import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'test_util.dart';

AtClient? atClient;

void main() async {
  try {
    final atsign = '@bob🛠';
    final preference = TestUtil.getBobPreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    atClient = atClientManager.atClient;
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
    var valueObject = atNotification.value!;
    var streamId = valueObject.split(':')[0];
    var fileName = valueObject.split(':')[1];
    var fileLength = int.parse(valueObject.split(':')[2]);
    fileName = utf8.decode(base64.decode(fileName));
    var userResponse = true; //UI user response
    if (userResponse == true) {
      print('user accepted transfer.Sending ack back');
      await atClient!.sendStreamAck(streamId, fileName, fileLength, fromAtSign,
          _streamCompletionCallBack, _streamReceiveCallBack);
    }
  } else {
    //TODO handle other notifications
    print('some other notification');
    print(atNotification);
  }
}

void _streamReceiveCallBack(var bytesReceived) {
  print('Receive callback bytes received: $bytesReceived');
}

void _streamCompletionCallBack(var streamId) {
  print('Transfer done for stream: $streamId');
}
