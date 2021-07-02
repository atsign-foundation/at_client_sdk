import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/stream_receiver.dart';
import 'package:at_client/src/stream/stream_sender.dart';
import 'package:uuid/uuid.dart';

class StreamHandler {
  static final StreamHandler _singleton = StreamHandler._internal();

  StreamHandler._internal();

  factory StreamHandler.getInstance() {
    return _singleton;
  }

  AtStream createStream(String currentAtSign, StreamType streamType,
      {String? streamId}) {
    streamId ??= Uuid().v4();
    var stream = AtStream(currentAtSign, streamId);
    if (streamType == StreamType.SEND) {
      stream.sender = StreamSender(streamId);
    } else if (streamType == StreamType.RECEIVE) {
      stream.receiver = StreamReceiver(currentAtSign, streamId);
    }
    return stream;
  }
}
