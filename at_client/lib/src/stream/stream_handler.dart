import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/stream_receiver_impl.dart';
import 'package:at_client/src/stream/stream_sender_impl.dart';
import 'package:uuid/uuid.dart';

class StreamHandler {
  static final StreamHandler _singleton = StreamHandler._internal();

  StreamHandler._internal();

  factory StreamHandler.getInstance() {
    return _singleton;
  }

  AtStream createStream(String currentAtSign, StreamType streamType,
      {String? streamId}) {
    var stream;
    if (streamType == StreamType.SEND) {
      stream = StreamSenderImpl(currentAtSign);
    } else if (streamType == StreamType.RECEIVE) {
      stream = StreamReceiverImpl(currentAtSign, streamId!);
    }
    return stream;
  }
}
