import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_utils/at_logger.dart';

class StreamNotificationHandler {
  RemoteSecondary? remoteSecondary;

  LocalSecondary? localSecondary;

  AtClientPreference? preference;

  EncryptionService? encryptionService;

  var logger = AtSignLogger('StreamNotificationHandler');

  Future<void> streamAck(AtStreamNotification streamNotification,
      Function streamCompletionCallBack, streamReceiveCallBack) async {
    var streamId = streamNotification.streamId;
    final secondaryAddress = await AtClientManager.getInstance()
        .secondaryAddressFinder!
        .findSecondary(streamNotification.senderAtSign);
    var host = secondaryAddress.host;
    var port = secondaryAddress.port;
    var socket = await SecureSocket.connect(host, port);
    // ignore: prefer_interpolation_to_compose_strings
    var f = File((preference!.downloadPath ?? '') +
        Platform.pathSeparator +
        'encrypted_${streamNotification.fileName}');
    logger.info('sending stream receive for : $streamId');
    var command = 'stream:receive $streamId\n';
    socket.write(command);
    var bytesReceived = 0;
    var firstByteSkipped = false;
    var sharedKey = await encryptionService!
        .getSharedKeyForDecryption(streamNotification.senderAtSign);
    socket.listen((onData) async {
      if (onData.length == 1 && onData.first == 64) {
        //skip @ prompt
        logger.finer('skipping prompt');
        return;
      }
      if (onData.first == 64 && firstByteSkipped == false) {
        onData = onData.sublist(1);
        firstByteSkipped = true;
        logger.finer('skipping @');
      }
      bytesReceived += onData.length;
      f.writeAsBytesSync(onData, mode: FileMode.append);
      streamReceiveCallBack(bytesReceived);
      if (bytesReceived == streamNotification.fileLength) {
        var startTime = DateTime.now();
        var decryptedBytes =
            encryptionService!.decryptStream(f.readAsBytesSync(), sharedKey);
        var decryptedFile = File((preference!.downloadPath ?? '') +
            Platform.pathSeparator +
            streamNotification.fileName);
        decryptedFile.writeAsBytesSync(decryptedBytes);
        f.deleteSync(); // delete encrypted file
        var endTime = DateTime.now();
        logger.info(
            'Decrypting stream data completed in ${endTime.difference(startTime).inMilliseconds} milliseconds');
        logger.info('Stream transfer complete:$streamId');
        socket.write('stream:done $streamId\n');
        streamCompletionCallBack(streamId);
        return;
      }
    }, onDone: () {
      socket.destroy();
    });
  }
}
