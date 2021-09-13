import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/at_stream_request.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_utils/at_logger.dart';
import 'test_util.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getAlicePreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atStreamRequest =
        AtStreamRequest('@bob🛠', '/home/murali/Pictures/@/dog.jpeg');
    atStreamRequest.namespace = 'atmosphere';
    final streamSender = atClientManager.streamService
        .createStream(StreamType.SEND) as StreamSender;
    var streamId1 =  streamSender.send(atStreamRequest, _onDone, _onError);
    print('sent stream : $streamId1');
    var atStreamRequest2 =
    AtStreamRequest('@bob🛠', '/home/murali/Pictures/@/cat.jpeg');
    atStreamRequest.namespace = 'atmosphere';
    var streamId2 =  streamSender.send(atStreamRequest2, _onDone, _onError);
    print('sent stream : $streamId2');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void _onDone(AtStreamResponse response) {
  print('stream done callback for streamId: ${response.streamId}');
  print(response);
}

void _onError(AtStreamResponse response) {
  print('stream error callback');
  print(response);
}
