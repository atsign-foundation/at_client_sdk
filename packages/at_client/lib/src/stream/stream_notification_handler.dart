import 'dart:convert';
import 'dart:io';

import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/lifecycle/lookups.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class StreamNotificationHandler {
  RemoteSecondary? remoteSecondary;

  LocalSecondary? localSecondary;

  AtClientPreference? preference;

  EncryptionService? encryptionService;

  AtTransportFactory? transportFactory;

  var logger = AtSignLogger('StreamNotificationHandler');

  Future<void> streamAck(AtStreamNotification streamNotification,
      Function streamCompletionCallBack, streamReceiveCallBack) async {
    var streamId = streamNotification.streamId;
    final secondaryAddress = await AtClientManager.getInstance()
        .secondaryAddressFinder!
        .findSecondary(streamNotification.senderAtSign);
    var host = secondaryAddress.host;
    var port = secondaryAddress.port.toString();
    var transport = await (transportFactory ?? defaultTransportFactory(preference)).connect(host, port);
    // ignore: prefer_interpolation_to_compose_strings
    var f = File('${preference!.downloadPath ?? ''}'
        '${Platform.pathSeparator}'
        'encrypted_${streamNotification.fileName}');
    logger.info('sending stream receive for : $streamId');
    var command = 'stream:receive $streamId\n';
    transport.add(utf8.encode(command));
    await transport.flush();
    var bytesReceived = 0;
    var firstByteSkipped = false;
    var sharedKey = await encryptionService!
        .getSharedKeyForDecryption(streamNotification.senderAtSign);
    transport.inbound.listen((onData) async {
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
        transport.add(utf8.encode('stream:done $streamId\n'));
        await transport.flush();
        streamCompletionCallBack(streamId);
        return;
      }
    }, onDone: () {
      transport.destroy();
    });
  }
}
