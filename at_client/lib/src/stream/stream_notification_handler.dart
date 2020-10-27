import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

class StreamNotificationHandler {
  RemoteSecondary remoteSecondary;

  LocalSecondary localSecondary;

  AtClientPreference preference;

  var logger = AtSignLogger('StreamNotificationHandler');

  Future<void> streamAck(AtStreamNotification streamNotification) async {
    var streamId = streamNotification.streamId;
    var secondaryUrl = await AtLookupImpl.findSecondary(
        streamNotification.senderAtSign,
        preference.rootDomain,
        preference.rootPort);
    var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];
    var socket = await SecureSocket.connect(host, int.parse(port));
    socket.write('from:${streamNotification.currentAtSign}\n');
    var f =
        await File('${preference.downloadPath}/${streamNotification.fileName}');
    var isStreamReady = false;
    var bytesReceived = 0;
    socket.listen((onData) async {
      if (isStreamReady) {
        bytesReceived += onData.length;
        f.writeAsBytesSync(onData, mode: FileMode.append);
        logger.finer('bytesReceived:${bytesReceived}');
        if (bytesReceived == streamNotification.fileLength) {
          logger.info('Stream transfer complete:${streamId}');
          socket.write('stream:done ${streamId}\n');
        }
        return;
      }
      var message = utf8.decode(onData);
      logger.finer('message:${message}');
      if (message.startsWith('data:proof:')) {
        message = message.trim();
        message = message.replaceFirst('data:proof:', '');
        var proof = message.split(':');
        var key = proof[0];
        var value = proof[1];
        value = value.replaceAll('@', '');
        value = value.replaceFirst('\n', '');
        var signingKeyBuilder = LLookupVerbBuilder()
          ..atKey = AT_SIGNING_PRIVATE_KEY
          ..sharedWith = streamNotification.currentAtSign
          ..sharedBy = streamNotification.currentAtSign;
        var signingKey = await localSecondary.executeVerb(signingKeyBuilder);
        if (signingKey != null) {
          signingKey = signingKey.replaceAll('data:', '');
        }
        var signedChallenge = AtClientUtil.signChallenge('$value', signingKey);
        logger.finer('challenge key:${key} value:${value}');
        var updateResult = await remoteSecondary.executeCommand(
            'update:public:${key} ${signedChallenge}\n',
            auth: true);
        logger.finer('update result:${updateResult}');
        if (updateResult == 'data:-1') {
          socket.write('pol\n');
        }
      } else if (message == '${streamNotification.currentAtSign}@') {
        logger.finer('pol success');
        var command = 'stream:receive ${streamId}\n';
        socket.write(command);
        isStreamReady = true;
      }
    }, onDone: () {
      socket.destroy();
    });
  }
}
