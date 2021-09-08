import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_ack.dart';
import 'package:at_client/src/stream/at_stream_request.dart';

abstract class AtStream {
  String currentAtSign;
  late AtClientPreference preference;
  EncryptionService? encryptionService;
  AtStream(this.currentAtSign);
  Future<void> cancel();
}

abstract class StreamSender extends AtStream {
  StreamSender(String currentAtSign)
      : super(currentAtSign);

  Future<String> send(
      AtStreamRequest atStreamRequest, Function onDone, Function onError);
}

abstract class StreamReceiver extends AtStream {
  String streamId;
  StreamReceiver(String currentAtSign, this.streamId)
      : super(currentAtSign);

  Future<void> ack(AtStreamAck atStreamAck, Function streamCompletionCallBack,
      Function streamProgressCallBack);
  Future<void> resume(String streamId, int startByte, String senderAtSign);
}

enum StreamType { SEND, RECEIVE }
