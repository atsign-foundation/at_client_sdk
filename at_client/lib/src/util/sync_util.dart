import 'dart:convert';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_commons/at_builders.dart';

class SyncUtil {
  static var logger = AtSignLogger('SyncUtil');
  static Future<CommitEntry> getCommitEntry(int sequenceNumber) async {
    var commitEntry = await AtCommitLog.getInstance().getEntry(sequenceNumber);
    return commitEntry;
  }

  static Future<void> updateCommitEntry(var commitEntry, int commitId) async {
    await AtCommitLog.getInstance().update(commitEntry, commitId);
  }

  static CommitEntry getLastSyncedEntry() {
    var lastEntry = AtCommitLog.getInstance().lastSyncedEntry();
    return lastEntry;
  }

  static Future<CommitEntry> getEntry(int seqNumber) async {
    var entry = await AtCommitLog.getInstance().getEntry(seqNumber);
    return entry;
  }

  static List<CommitEntry> getChangesSinceLastCommit(int seqNum) {
    return AtCommitLog.getInstance().getChanges(seqNum);
  }

  //#TODO change return type to enum which says in sync, local ahead or server ahead
  static bool isInSync(List<CommitEntry> unCommittedEntries, int serverCommitId,
      int lastSyncedCommitId) {
    logger.info('localCommitId:${lastSyncedCommitId}');
    logger.info('serverCommitId:${serverCommitId}');
    logger.info('changed entries: ${unCommittedEntries?.length}');
    return (unCommittedEntries == null || unCommittedEntries.isEmpty) &&
        _checkCommitIdsEqual(lastSyncedCommitId, serverCommitId);
  }

  static bool _checkCommitIdsEqual(lastSyncedCommitId, serverCommitId) {
    return (lastSyncedCommitId != null &&
            serverCommitId != null &&
            lastSyncedCommitId == serverCommitId) ||
        (lastSyncedCommitId == null && serverCommitId == null);
  }

  static Future<int> getLatestServerCommitId(
      RemoteSecondary remoteSecondary) async {
    var commitId;
    var builder = StatsVerbBuilder()..statIds = '3';
    var result = await remoteSecondary.executeVerb(builder);
    if (result != null) {
      result = result.replaceAll('data: ', '');
      var statsJson = jsonDecode(result);
      print(statsJson);
      if (statsJson[0]['value'] != 'null') {
        commitId = int.parse(statsJson[0]['value']);
      }
    }
    return commitId;
  }

  static bool shouldSkipSync(String key) {
    if (key.startsWith(AT_PKAM_PRIVATE_KEY) ||
        key.startsWith(AT_PKAM_PUBLIC_KEY) ||
        key.startsWith(AT_ENCRYPTION_PRIVATE_KEY)) {
      return true;
    }
    return false;
  }
}
