import 'package:at_client/src/stream/stream_receiver.dart';
import 'package:at_client/src/stream/stream_sender.dart';

class AtStream {
  String streamId;
  String currentAtSign;
  StreamSender? sender;
  StreamReceiver? receiver;
  AtStream(this.currentAtSign, this.streamId);
}

enum StreamType { SEND, RECEIVE }
