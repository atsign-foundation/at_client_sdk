import 'dart:convert';
import 'dart:io';
import 'package:async/async.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/converters/encryption/aes_converter.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_request.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:path/path.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_commons/at_commons.dart';

class StreamSender {
  String streamId;

  StreamSender(this.streamId);

  late RemoteSecondary remoteSecondary;

  EncryptionService? encryptionService;

  final _logger = AtSignLogger('StreamSender');

  final chunkSize = 1024;

  /// Sends a file specified in [atStreamRequest.filePath] through a stream verb.
  /// onDone[AtStreamResponse] is called upon stream completion.
  /// onError[AtStreamResponse] is called when stream errors out.
  /// If a stream transfer has to be resumed then specify [atStreamRequest.startByte]. Stream transfer will be resumed from startByte.
  Future<void> send(AtStreamRequest atStreamRequest, Function onDone,
      Function onError) async {
    var atStreamResponse = AtStreamResponse(streamId);
    try {
      var file = File(atStreamRequest.filePath);
      final fileLength = await file.length();
      var fileName = basename(atStreamRequest.filePath);
      fileName = base64.encode(utf8.encode(fileName));
      var command =
          'stream:init${atStreamRequest.receiverAtSign} namespace:${atStreamRequest.namespace} startByte:${atStreamRequest.startByte} $streamId $fileName $fileLength\n';
      _logger.finer('sending stream init:$command');
      await _checkConnectivity();
      var result = await remoteSecondary.executeCommand(command, auth: true);
      if (result != null && result.startsWith('stream:ack')) {
        result = result.replaceAll('stream:ack ', '');
        result = result.trim();
        _logger.finer('ack received for streamId:$streamId');
        await _startStream(
            file, atStreamRequest.receiverAtSign, atStreamRequest.startByte);
        var streamResult =
            await remoteSecondary.atLookUp.messageListener!.read();
        if (streamResult != null && streamResult.startsWith('stream:done')) {
          _logger.finer('stream done - streamId: $streamId');
          atStreamResponse.status = AtStreamStatus.COMPLETE;
          onDone(atStreamResponse);
        }
      } else if (result != null && result.startsWith('error:')) {
        result = result.replaceAll('error:', '');
        atStreamResponse.status = AtStreamStatus.ERROR;
        atStreamResponse.errorCode = result.split('-')[0];
        atStreamResponse.errorMessage = result.split('-')[1];
        onError(atStreamResponse);
      } else {
        atStreamResponse.status = AtStreamStatus.NO_ACK;
        onError(atStreamResponse);
      }
    } on Exception catch (e) {
      atStreamResponse.errorMessage = e.toString();
      onError(atStreamResponse);
    }
  }

  Future<void> _startStream(
      File file, String receiverAtSign, int startByte) async {
    var readBytes = 0;
    final length = await file.length();
    var chunkedStream = ChunkedStreamReader(file.openRead(startByte));
    try {
      var encryptionKey =
          await encryptionService!.getStreamEncryptionKey(receiverAtSign);
      while (readBytes < length) {
        remoteSecondary.atLookUp.connection!.getSocket().add(
            AESCodec(encryptionKey)
                .encoder
                .convert(await chunkedStream.readBytes(chunkSize)));
        readBytes += chunkSize;
      }
    } finally {
      await chunkedStream.cancel();
    }
  }

  /// Cancels a [atStreamRequest]
  /// onDone[AtStreamResponse] gets called upon successful completion of cancel request
  /// onError[AtStreamResponse] gets called upon failure of the cancel request
  Future<void> cancel(AtStreamRequest atStreamRequest, Function onDone,
      Function onError) async {
    var atStreamResponse = AtStreamResponse(streamId);
    try {
      var command = 'stream:cancel $streamId';
      await _checkConnectivity();
      var result = await remoteSecondary.executeCommand(command, auth: true);
      //#TODO process result
      atStreamResponse.status = AtStreamStatus.CANCELLED;
      onDone(atStreamResponse);
    } on Exception catch (e) {
      atStreamResponse.errorMessage = e.toString();
      onError(atStreamResponse);
    }
  }

  Future<void> _checkConnectivity() async {
    if (!(await NetworkUtil.isNetworkAvailable())) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await remoteSecondary.isAvailable())) {
      throw AtConnectException('Secondary server is unavailable');
    }
  }
}
