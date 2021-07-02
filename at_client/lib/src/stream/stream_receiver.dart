import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_ack.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';

class StreamReceiver {
  String streamId;

  late RemoteSecondary remoteSecondary;

  EncryptionService? encryptionService;

  late AtClientPreference preference;

  final String _currentAtSign;

  StreamReceiver(this._currentAtSign, this.streamId);

  Future<void> ack(AtStreamAck atStreamAck, Function streamCompletionCallBack,
      Function streamProgressCallBack) async {
    var handler = StreamNotificationHandler();
    handler.remoteSecondary = remoteSecondary;
    handler.preference = preference;
    handler.encryptionService = encryptionService;
    var notification = AtStreamNotification()
      ..streamId = streamId
      ..fileName = atStreamAck.fileName!
      ..currentAtSign = _currentAtSign
      ..senderAtSign = atStreamAck.senderAtSign!
      ..fileLength = atStreamAck.fileLength!;
    print('Sending ack for stream notification:$notification');
    await handler.streamAck(
        notification, streamCompletionCallBack, streamProgressCallBack);
  }

  Future<void> resume() async {
    //#TODO implement
  }

  Future<void> cancel() async {
    //#TODO implement
  }
}
