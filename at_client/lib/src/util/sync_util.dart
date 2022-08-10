import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

class SyncUtil {
  static var logger = AtSignLogger('SyncUtil');

  static Future<CommitEntry?> getCommitEntry(
      int sequenceNumber, String atSign) async {
    var commitLogInstance =
        await (AtCommitLogManagerImpl.getInstance().getCommitLog(atSign));
    var commitEntry = await commitLogInstance?.getEntry(sequenceNumber);
    return commitEntry;
  }

  static Future<void> updateCommitEntry(
      var commitEntry, int commitId, String atSign) async {
    var commitLogInstance =
        await (AtCommitLogManagerImpl.getInstance().getCommitLog(atSign));
    logger.finer(
        'Updating commit log entry $commitEntry with commitId $commitId');
    await commitLogInstance?.update(commitEntry, commitId);
  }

  static Future<CommitEntry?> getLastSyncedEntry(String? regex,
      {required String atSign}) async {
    var commitLogInstance =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);

    CommitEntry? lastEntry;
    if (regex != null) {
      lastEntry = await commitLogInstance!.lastSyncedEntryWithRegex(regex);
    } else {
      lastEntry = await commitLogInstance!.lastSyncedEntry();
    }
    return lastEntry;
  }

  static Future<CommitEntry?> getEntry(int? seqNumber, String atSign) async {
    var commitLogInstance = await (AtCommitLogManagerImpl.getInstance()
        .getCommitLog(atSign) as FutureOr<AtCommitLog>);
    var entry = await commitLogInstance.getEntry(seqNumber);
    return entry;
  }

  static Future<List<CommitEntry>> getChangesSinceLastCommit(
      int? seqNum, String? regex,
      {required String atSign}) async {
    var commitLogInstance =
        await (AtCommitLogManagerImpl.getInstance().getCommitLog(atSign));
    if (commitLogInstance == null) {
      return [];
    }
    return commitLogInstance.getChanges(seqNum, regex);
  }

  //#TODO change return type to enum which says in sync, local ahead or server ahead
  static bool isInSync(List<CommitEntry?>? unCommittedEntries,
      int? serverCommitId, int? lastSyncedCommitId) {
    logger.finer('localCommitId:$lastSyncedCommitId');
    logger.finer('serverCommitId:$serverCommitId');
    logger.finer('changed entries: ${unCommittedEntries?.length}');
    return (unCommittedEntries == null || unCommittedEntries.isEmpty) &&
        _checkCommitIdsEqual(lastSyncedCommitId, serverCommitId);
  }

  static bool _checkCommitIdsEqual(lastSyncedCommitId, serverCommitId) {
    return (lastSyncedCommitId != null &&
            serverCommitId != null &&
            lastSyncedCommitId == serverCommitId) ||
        (lastSyncedCommitId == null && serverCommitId == null);
  }

  /// throws [AtClientException] if there is an issue processing stats verb on server or
  /// server is not reachable
  static Future<int?> getLatestServerCommitId(
      RemoteSecondary remoteSecondary, String? regex) async {
    int? commitId;
    var builder = StatsVerbBuilder()..statIds = '3';
    if (regex != null && regex != 'null' && regex.isNotEmpty) {
      builder.regex = regex;
    }
    // ignore: prefer_typing_uninitialized_variables
    var result;
    try {
      result = await remoteSecondary.executeVerb(builder);
    } on AtClientException catch (e) {
      logger
          .severe('Exception occurred in processing stats verb ${e.toString}');
      rethrow;
    } on Exception catch (e) {
      logger.severe(
          'Exception while getting latest server commit id: ${e.toString()}');
      throw AtClientException.message(
          'Unable to fetch latest server commit id: ${e.toString()}');
    }
    result = result.replaceAll('data: ', '');
    var statsJson = JsonUtils.decodeJson(result);
    if (statsJson[0]['value'] != 'null') {
      commitId = int.parse(statsJson[0]['value']);
    }
    return commitId;
  }

  /// Returns true for the keys that has to be sync'ed to the server
  /// Else returns false.
  ///
  /// The PKAM keys and Encryption Private key should not be sync'ed to remote secondary
  static bool shouldSync(String key) {
    if (key.startsWith(AT_PKAM_PRIVATE_KEY) ||
        key.startsWith(AT_PKAM_PUBLIC_KEY) ||
        key.startsWith(AT_ENCRYPTION_PRIVATE_KEY) ||
        key.startsWith(statsNotificationId)) {
      return false;
    }
    return true;
  }
}
