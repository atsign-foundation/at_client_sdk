import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/converters/encryption/aes_converter.dart';
import 'package:at_client/src/converters/byte_splitter.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class StreamNotificationHandler {
  AtClientPreference? preference;

  EncryptionService? encryptionService;

  final chunkSize = 1024;

  var _logger = AtSignLogger('StreamNotificationHandler');

  Future<void> streamAck(AtStreamNotification streamNotification,
      Function streamCompletionCallBack, streamProgressCallBack) async {
    var streamId = streamNotification.streamId;
    var secondaryUrl = await AtLookupImpl.findSecondary(
        streamNotification.senderAtSign,
        preference!.rootDomain,
        preference!.rootPort);
    var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];
    var socket = await SecureSocket.connect(host, int.parse(port));
    _logger.info('sending stream receive for : $streamId');
    var command = 'stream:receive $streamId\n';
    socket.write(command);
    var bytesReceived = 0, partialTransferSize = 0;
    var firstByteSkipped = false;
    var decryptedFile =
        File('${preference!.downloadPath}/${streamNotification.fileName}');
    if (decryptedFile.existsSync()) {
      partialTransferSize = await decryptedFile.length();
    }
    _logger.finer('partial transfer size: $partialTransferSize');
    bytesReceived += partialTransferSize;
    var sharedKey;
    socket.listen((onData) async {
      if (onData.length == 1 && onData.first == 64) {
        //skip @ prompt
        _logger.finer('skipping prompt');
        return;
      }
      if (onData.first == 64 && firstByteSkipped == false) {
        onData = onData.sublist(1);
        firstByteSkipped = true;
        _logger.finer('skipping @');
      }
      sharedKey ??= await encryptionService!
          .getSharedKey(streamNotification.senderAtSign);

      Splitter(chunkSize).convert(onData).forEach((fileChunk) {
        _logger.finer('encrypted data length received ${onData.length}');
        var decryptedBytes = AESCodec(sharedKey).decoder.convert(fileChunk);
        decryptedFile.writeAsBytesSync(decryptedBytes, mode: FileMode.append);
      });
      bytesReceived += onData.length;
      streamProgressCallBack(bytesReceived);
      if (bytesReceived == streamNotification.fileLength) {
        _logger.info('Stream transfer complete:$streamId');
        socket.write('stream:done $streamId\n');
        streamCompletionCallBack(streamId);
        return;
      }
    }, onDone: () {
      socket.destroy();
    });
  }
}
