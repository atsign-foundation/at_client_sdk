import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_client/src/stream/at_stream_ack.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class StreamReceiverImpl extends StreamReceiver {
  final _logger = AtSignLogger('StreamReceiverImpl');

  StreamReceiverImpl(String currentAtSign, String streamId)
      : super(currentAtSign, streamId);

  /// Acknowledges a stream transfer from [atStreamAck.senderAtSign]
  /// Upon stream completion [streamCompletionCallBack] is triggered with the streamId for the transfer.
  /// App can use [streamProgressCallBack] to know the total bytes received so far for the acknowledged transfer.
  Future<void> ack(AtStreamAck atStreamAck, Function streamCompletionCallBack,
      Function streamProgressCallBack) async {
    var handler = StreamNotificationHandler();
    handler.preference = preference;
    handler.encryptionService = encryptionService;
    var notification = AtStreamNotification()
      ..streamId = streamId
      ..fileName = atStreamAck.fileName!
      ..currentAtSign = super.currentAtSign
      ..senderAtSign = atStreamAck.senderAtSign!
      ..fileLength = atStreamAck.fileLength!;
    _logger.finer('Sending ack for stream notification:$notification');
    await handler.streamAck(
        notification, streamCompletionCallBack, streamProgressCallBack);
  }

  /// Initiates a stream resume from receiver to the [senderAtSign] from the byte [startByte]
  Future<void> resume(
      String streamId, int startByte, String senderAtSign) async {
    var secondaryUrl = await AtLookupImpl.findSecondary(
        senderAtSign, preference.rootDomain, preference.rootPort);
    var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];
    var socket = await SecureSocket.connect(host, int.parse(port));
    _logger.info('sending stream receive for : $streamId');
    var command =
        'stream:resume${super.currentAtSign} namespace:${preference.namespace} startByte:$startByte $streamId\n';
    socket.write(command);
  }

  Future<void> cancel() async {
    //#TODO implement
  }
}
