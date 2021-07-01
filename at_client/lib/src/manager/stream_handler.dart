import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/stream/stream.dart';
import 'package:at_client/src/stream/stream_receiver.dart';
import 'package:at_client/src/stream/stream_sender.dart';
import 'package:uuid/uuid.dart';

class StreamHandler {
  static final StreamHandler _singleton = StreamHandler._internal();

  StreamHandler._internal();

  factory StreamHandler.getInstance() {
    return _singleton;
  }

  Stream createStream(String currentAtSign, StreamType streamType,
      {String? streamId}) {
    streamId ??= Uuid().v4();
    var stream = Stream(currentAtSign, streamId);
    if (streamType == StreamType.SEND) {
      stream.sender = StreamSender(streamId);
    } else if (streamType == StreamType.RECEIVE) {
      stream.receiver = StreamReceiver(streamId);
    }
    return stream;
  }
}
