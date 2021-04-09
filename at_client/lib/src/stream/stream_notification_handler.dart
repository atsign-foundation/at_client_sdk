import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class StreamNotificationHandler {
  RemoteSecondary remoteSecondary;

  LocalSecondary localSecondary;

  AtClientPreference preference;

  EncryptionService encryptionService;

  var logger = AtSignLogger('StreamNotificationHandler');

  Future<void> streamAck(AtStreamNotification streamNotification,
      Function streamCompletionCallBack, streamReceiveCallBack) async {
    var streamId = streamNotification.streamId;
    var secondaryUrl = await AtLookupImpl.findSecondary(
        streamNotification.senderAtSign,
        preference.rootDomain,
        preference.rootPort);
    var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];
    var socket = await SecureSocket.connect(host, int.parse(port));
    var f = File('${preference.downloadPath}/${streamNotification.fileName}');
    logger.info('sending stream receive for : $streamId');
    var command = 'stream:receive $streamId\n';
    socket.write(command);
    var bytesReceived = 0;
    var sharedKey =
        await encryptionService.getSharedKey(streamNotification.senderAtSign);
    socket.listen((onData) async {
      if (onData.length == 1 && onData.first == 64) {
        //skip @ prompt
        return;
      }
      bytesReceived += onData.length;
      var decryptedBytes = encryptionService.decryptStream(onData, sharedKey);
      f.writeAsBytesSync(decryptedBytes, mode: FileMode.append);
      logger.finer('bytesReceived:$bytesReceived');
      streamReceiveCallBack(bytesReceived);
      if (bytesReceived == streamNotification.fileLength) {
        var startTime = DateTime.now();
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
