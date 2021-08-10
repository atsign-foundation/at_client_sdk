import 'dart:async';
import 'dart:convert';

import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
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
    await commitLogInstance?.update(commitEntry, commitId);
  }

  static Future<CommitEntry?> getLastSyncedEntry(String? regex,
      {required String atSign}) async {
    var commitLogInstance =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);

    var lastEntry;
    if (regex != null) {
      lastEntry = commitLogInstance!.lastSyncedEntryWithRegex(regex);
    } else {
      lastEntry = commitLogInstance!.lastSyncedEntry();
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

  static Future<int?> getLatestServerCommitId(
      RemoteSecondary remoteSecondary, String? regex) async {
    var commitId;
    var builder = StatsVerbBuilder()..statIds = '3';
    if (regex != null && regex != 'null' && regex.isNotEmpty) {
      builder.regex = regex;
    }
    var result = await remoteSecondary.executeVerb(builder);
    result = result.replaceAll('data: ', '');
    var statsJson = jsonDecode(result);
    print(statsJson);
    if (statsJson[0]['value'] != 'null') {
      commitId = int.parse(statsJson[0]['value']);
    }
    return commitId;
  }

  static bool shouldSkipSync(String key) {
    if (key.startsWith(AT_PKAM_PRIVATE_KEY) ||
        key.startsWith(AT_PKAM_PUBLIC_KEY) ||
        key.startsWith(AT_ENCRYPTION_PRIVATE_KEY) || key.startsWith('_')) {
      return true;
    }
    return false;
  }
}
