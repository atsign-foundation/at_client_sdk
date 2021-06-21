import 'package:at_client/at_client.dart';
import 'package:at_client/src/stream/stream_receiver.dart';
import 'package:at_client/src/stream/stream_sender.dart';

class Stream {
  String streamId;
  String currentAtSign;
  StreamSender? sender;
  StreamReceiver? receiver;
  Stream(this.currentAtSign, this.streamId);
}

enum StreamType{SEND, RECEIVE}