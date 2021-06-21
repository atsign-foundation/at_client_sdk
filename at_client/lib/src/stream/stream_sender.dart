import 'package:at_client/src/stream/at_stream_request.dart';
import 'package:uuid/uuid.dart';

class StreamSender {
  String streamId;

  StreamSender(this.streamId);

  /// onDone[AtStreamResponse]
  /// onError[AtStreamResponse]
  Future<void> send(AtStreamRequest atStreamRequest) async {
    var streamId = Uuid().v4();
    //#TODO implement
  }

  Future<void> cancel() async {
    //#TODO implement
  }
}
