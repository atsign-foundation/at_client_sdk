import 'dart:convert';
import 'dart:io';
import 'package:at_client/src/client/remote_secondary.dart';
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

  /// onDone[AtStreamResponse]
  /// onError[AtStreamResponse]
  Future<void> send(AtStreamRequest atStreamRequest) async {
    var atStreamResponse = AtStreamResponse(streamId);
    try {
      var file = File(atStreamRequest.filePath);
      //#TODO if startByte is set..read only from startByte
      var data = file.readAsBytesSync();
      var fileName = basename(atStreamRequest.filePath);
      fileName = base64.encode(utf8.encode(fileName));
      var encryptedData = await encryptionService!
          .encryptStream(data, atStreamRequest.receiverAtSign);
      var command =
          'stream:init${atStreamRequest.receiverAtSign} namespace:${atStreamRequest.namespace} $streamId $fileName ${encryptedData.length}\n';
      _logger.finer('sending stream init:$command');
      await _checkConnectivity();
      var result = await remoteSecondary.executeCommand(command, auth: true);
      //#TODO wait for ack and send data through socket
      atStreamResponse.status = AtStreamStatus.COMPLETE;
      atStreamRequest.onDone(atStreamResponse);
    } on Exception catch (e) {
      atStreamResponse.errorMessage = e.toString();
      atStreamRequest.onError(atStreamResponse);
    }
  }

  Future<void> cancel(AtStreamRequest atStreamRequest) async {
    var atStreamResponse = AtStreamResponse(streamId);
    try {
      var command = 'stream:cancel $streamId';
      await _checkConnectivity();
      var result = await remoteSecondary.executeCommand(command, auth: true);
      //#TODO process result
      atStreamResponse.status = AtStreamStatus.CANCELLED;
      atStreamRequest.onDone(atStreamResponse);
    } on Exception catch (e) {
      atStreamResponse.errorMessage = e.toString();
      atStreamRequest.onError(atStreamResponse);
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
