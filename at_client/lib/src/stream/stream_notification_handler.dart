import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/converters/encryption/aes_converter.dart';
import 'package:at_client/src/converters/splitter.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class StreamNotificationHandler {
  RemoteSecondary? remoteSecondary;

  AtClientPreference? preference;

  EncryptionService? encryptionService;

  final chunkSize = 1024;

  var logger = AtSignLogger('StreamNotificationHandler');

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
    logger.info('sending stream receive for : $streamId');
    var command = 'stream:receive $streamId\n';
    socket.write(command);
    var bytesReceived = 0;
    var firstByteSkipped = false;
    var sharedKey =
        await encryptionService!.getSharedKey(streamNotification.senderAtSign);
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
      var decryptedFile =
          File('${preference!.downloadPath}/${streamNotification.fileName}');
      Splitter(chunkSize).convert(onData).forEach((fileChunk) {
        logger.finer('encrypted data received ${onData.length}');
        logger.info('Encrypted Bytes in stream receiver : ${fileChunk}');
        logger.info('Decrypted Bytes in stream receiver : ${AESCodec(sharedKey).decoder.convert(fileChunk)}');
        logger.info('Decrypted data in stream receiver : ${utf8.decode(AESCodec(sharedKey).decoder.convert(fileChunk))}');
        decryptedFile.writeAsBytesSync(
            AESCodec(sharedKey).decoder.convert(fileChunk),
            mode: FileMode.append);
      });
      bytesReceived += onData.length;
      streamProgressCallBack(bytesReceived);
      if (bytesReceived == streamNotification.fileLength) {
        logger.info('Stream transfer complete:$streamId');
        socket.write('stream:done $streamId\n');
        streamCompletionCallBack(streamId);
        return;
      }
    }, onDone: () {
      socket.destroy();
    });
  }

  Future<void> streamResume(AtStreamNotification streamNotification, Function streamCompletionCallBack, Function streamProgressCallBack) async {
    var streamId = streamNotification.streamId;
    var secondaryUrl = await AtLookupImpl.findSecondary(
        streamNotification.senderAtSign,
        preference!.rootDomain,
        preference!.rootPort);
    var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];
    var socket = await SecureSocket.connect(host, int.parse(port));
    logger.info('sending stream receive for : $streamId');
    var command = 'stream:resume${streamNotification.currentAtSign} namespace:${streamNotification.namespace} startByte:${streamNotification.startByte} $streamId ${streamNotification.fileName} ${streamNotification.fileLength}\n';
    socket.write(command);
    var bytesReceived = 0;
    var firstByteSkipped = false;
    var sharedKey =
    await encryptionService!.getSharedKey(streamNotification.senderAtSign);
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
      var decryptedFile =
      File('${preference!.downloadPath}/${streamNotification.fileName}');
      Splitter(chunkSize).convert(onData).forEach((fileChunk) {
        logger.finer('encrypted data received ${onData.length}');
        decryptedFile.writeAsBytesSync(
            AESCodec(sharedKey).decoder.convert(fileChunk),
            mode: FileMode.append);
      });
      bytesReceived += onData.length;
      streamProgressCallBack(bytesReceived);
      if (bytesReceived == streamNotification.fileLength) {
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
