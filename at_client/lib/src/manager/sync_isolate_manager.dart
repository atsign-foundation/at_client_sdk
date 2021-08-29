import 'dart:convert';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';

class SyncIsolateManager {
  static final SyncIsolateManager _singleton = SyncIsolateManager._internal();

  SyncIsolateManager._internal();

  factory SyncIsolateManager.getInstance() {
    return _singleton;
  }

  static var logger = AtSignLogger('SyncIsolateManager');

  static void syncImmediateIsolate(SendPort sendPort) {
    try {
      var isolateReceive = ReceivePort();
      sendPort.send(isolateReceive.sendPort);
      isolateReceive.listen((message) async {
        var builder = message['builder'];
        var atSign = message['atsign'];
        var preference = message['preference'];
        var privateKey = message['privateKey'];
        var remoteSecondary =
            RemoteSecondary(atSign, preference, privateKey: privateKey);
        var verbResult = await remoteSecondary.executeVerb(builder);
        logger.info('syncIsolate result:$verbResult');
        var serverCommitId = verbResult.split(':')[1];
        sendPort.send(serverCommitId);
      });
    } on Exception catch (e) {
      logger.severe('exception in syncImmediateIsolate ${e.toString()}');
    }
  }

  static void executeRemoteCommandIsolate(SendPort sendPort) async {
    try {
      var isolateReceive = ReceivePort();
      sendPort.send(isolateReceive.sendPort);
      isolateReceive.listen((message) async {
        var operation = message['operation'];
        var atSign = message['atsign'];
        var preference = message['preference'];
        var privateKey = message['private_key'];
        var remoteSecondary =
            RemoteSecondary(atSign, preference, privateKey: privateKey);

        switch (operation) {
          case 'get_commit_id':
            // Send stats verb to get latest server commit id.
            var commitId;
            var builder = StatsVerbBuilder()..statIds = '3';
            var result = await remoteSecondary.executeVerb(builder);
            result = result.replaceAll('data: ', '');
            var statsJson = jsonDecode(result);
            if (statsJson[0]['value'] != 'null') {
              commitId = int.parse(statsJson[0]['value']);
            }
            var isolateResult = <String, dynamic>{};
            isolateResult['operation'] = 'get_commit_id_result';
            isolateResult['commit_id'] = commitId;
            sendPort.send(isolateResult);
            break;
          case 'get_server_commits':
            // send sync verb to get latest changes from server
            var lastSyncedId = message['last_synced_commit_id'];
            var result = await remoteSecondary.sync(lastSyncedId);
            var isolateResult = <String, dynamic>{};
            isolateResult['operation'] = 'get_server_commits_result';
            isolateResult['sync_response'] = result;
            sendPort.send(isolateResult);
            break;
          case 'push_to_remote':
            // execute update/delete verb on server
            var builder = message['builder'];
            var result = await remoteSecondary.executeVerb(builder);
            var serverCommitId = result.split(':')[1];
            var isolateResult = <String, dynamic>{};
            isolateResult['operation'] = 'push_to_remote_result';
            isolateResult['operation_commit_id'] = serverCommitId;
            isolateResult['entry_key'] = message['entry_key'];
            logger.info(
                'pushed to remote:${builder.atKey}:${builder.sharedWith} ${isolateResult['entry_key']} $serverCommitId');
            sendPort.send(isolateResult);
            break;
        }
      });
    } on Exception catch (e) {
      logger.severe('exception in executeRemoteCommandIsolate ${e.toString()}');
    }
  }
}
