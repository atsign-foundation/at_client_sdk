import 'package:at_client/src/stream/at_stream_request.dart';

class StreamReceiver {
  String streamId;

  StreamReceiver(this.streamId);

  Future<void> ack(AtStreamRequest atStreamRequest) async {
    //#TODO implement
  }

  Future<void> resume() async {
    //#TODO implement
  }

  Future<void> cancel() async {
    //#TODO implement
  }
}
