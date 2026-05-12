import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

/// Class contains all the util methods that perform CRUD operations on the commit log keystore.
///
/// **Partially deprecated**: the client→server sync push path
/// drains `LocalSecondary.AtSyncQueue` directly rather than
/// scanning the commit log. The commit log itself is still the
/// substrate for client-side compaction and for downstream callers
/// of [getLastSyncedEntry], so commitId back-writes after each
/// successful push (and after each pull) are still required. The
/// methods marked `@Deprecated` here are the ones with no current
/// caller (read-side scans of `getChangesSinceLastCommit` etc.) and
/// are scheduled for removal.
///
/// Still in use (NOT deprecated):
///
/// * [getLatestServerCommitId] — `_getServerCommitId` calls this on
///   each cold-fetch / forced-fresh round.
/// * [shouldSync] (static) — general filter for which keys should
///   ever leave this device.
/// * [getLatestCommitEntry] — used by `_pushFromSyncQueue` to find
///   the entry to stamp the server-assigned commitId on.
/// * [getCommitEntry] — used by `_pullToLocal` to find the entry
///   that `executeVerb` just appended.
/// * [updateCommitEntry] — used by both `_pushFromSyncQueue` and
///   `_pullToLocal` to stamp the server-side commitId.
class SyncUtil {
  static var logger = AtSignLogger('SyncUtil');

  AtCommitLog? atCommitLog;

  SyncUtil({this.atCommitLog});

  /// Returns the commit-log entry at [sequenceNumber] for [atSign].
  /// Used by `_pullToLocal` to find the entry that the local apply
  /// just appended, so its commitId can be stamped with the server's
  /// value (required by client-side commit-log compaction).
  Future<CommitEntry?> getCommitEntry(int sequenceNumber, String atSign) async {
    atCommitLog ??=
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);

    var commitEntry = await atCommitLog?.getEntry(sequenceNumber);
    return commitEntry;
  }

  /// Stamps [commitId] onto [commitEntry] in the local commit log
  /// for [atSign]. Called from both push and pull paths in
  /// `SyncServiceImpl` — required for client-side commit-log
  /// compaction (which only compacts entries with non-null commitId)
  /// and for [getLastSyncedEntry] to return a meaningful high-water
  /// mark to downstream callers.
  Future<void> updateCommitEntry(
      CommitEntry commitEntry, int commitId, String atSign) async {
    atCommitLog ??=
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);
    await atCommitLog?.update(commitEntry, commitId);
  }

  /// Returns the latest commit-log entry with a non-null commitId
  /// (i.e. the most recently sync'd entry) for [atSign], optionally
  /// filtered by [regex]. SyncServiceImpl itself doesn't consult
  /// this method — its cursors live in `_highestPushedCommitId` and
  /// `lastReceivedServerCommitId`. But the back-writes that
  /// `_pushFromSyncQueue` and `_pullToLocal` perform onto the commit
  /// log keep the entries' commitId fields current, so this method
  /// keeps returning a meaningful answer for downstream callers and
  /// for the functional test pack.
  Future<CommitEntry?> getLastSyncedEntry(String? regex,
      {required String atSign}) async {
    atCommitLog ??=
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);

    CommitEntry? lastEntry;
    if (regex != null) {
      lastEntry = await atCommitLog?.lastSyncedEntryWithRegex(regex);
    } else {
      lastEntry = await atCommitLog?.lastSyncedEntry();
    }
    return lastEntry;
  }

  @Deprecated('No longer used by SyncServiceImpl. Scheduled for removal.')
  static Future<CommitEntry?> getEntry(int? seqNumber, String atSign) async {
    var commitLogInstance = await (AtCommitLogManagerImpl.getInstance()
        .getCommitLog(atSign) as FutureOr<AtCommitLog>);
    var entry = await commitLogInstance.getEntry(seqNumber);
    return entry;
  }

  @Deprecated('No longer used by SyncServiceImpl. The push path '
      'reads from `LocalSecondary.AtSyncQueue` instead of the '
      'commit log. Scheduled for removal.')
  Future<List<CommitEntry>> getChangesSinceLastCommit(
      int? seqNum, String? regex,
      {required String atSign}) async {
    atCommitLog ??=
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);
    if (atCommitLog == null) {
      return [];
    }
    return (await atCommitLog!.getChanges(seqNum, regex))
        .where((commitEntry) => !commitEntry.atKey!.startsWith('local:'))
        .toList();
  }

  //#TODO change return type to enum which says in sync, local ahead or server ahead
  @Deprecated('No longer used by SyncServiceImpl. The private '
      '`_isInSync` consults `LocalSecondary.syncQueueSize` and '
      '`lastReceivedServerCommitId` directly. Scheduled for removal.')
  static bool isInSync(List<CommitEntry?>? unCommittedEntries,
      int? serverCommitId, int? lastReceivedServerCommitId) {
    logger.finer('lastReceivedServerCommitId:$lastReceivedServerCommitId');
    logger.finer('serverCommitId:$serverCommitId');
    logger.finer('changed entries: ${unCommittedEntries?.length}');
    return (unCommittedEntries == null || unCommittedEntries.isEmpty) &&
        _checkCommitIdsEqual(lastReceivedServerCommitId, serverCommitId);
  }

  static bool _checkCommitIdsEqual(
      int? lastSyncedCommitId, int? serverCommitId) {
    return (lastSyncedCommitId != null &&
            serverCommitId != null &&
            lastSyncedCommitId == serverCommitId) ||
        (lastSyncedCommitId == null && serverCommitId == null);
  }

  /// throws [AtClientException] if there is an issue processing stats verb on server or
  /// server is not reachable
  Future<int?> getLatestServerCommitId(
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
    result = result.replaceFirst(RegExp('^data:'), '');
    var statsJson = JsonUtils.decodeJson(result);
    if (statsJson[0]['value'] != 'null') {
      commitId = int.parse(statsJson[0]['value']);
    }
    return commitId;
  }

  /// Returns true for the keys that has to be synced to the server
  /// Else returns false.
  ///
  /// The PKAM keys and Encryption Private key should not be synced to remote secondary
  static bool shouldSync(String key) {
    if (key.startsWith(AtConstants.atPkamPrivateKey) ||
        key.startsWith(AtConstants.atPkamPublicKey) ||
        key.startsWith(AtConstants.atEncryptionPrivateKey) ||
        key.startsWith(NotificationServiceImpl.notificationIdKey) ||
        key.startsWith(NotificationServiceImpl.lastReceivedNotificationKey)) {
      return false;
    }
    return true;
  }

  /// Returns the latest [CommitEntry] of the given key from the given atCommitLog instance
  /// If the key is not found [NullCommitEntry] is returned.
  Future<CommitEntry> getLatestCommitEntry(
      AtCommitLog atCommitLog, String key) async {
    var values = (await atCommitLog.commitLogKeyStore.toMap()).values.toList()
      ..sort(_compareCommitId);
    for (CommitEntry commitEntry in values) {
      if (commitEntry.atKey == key) {
        return commitEntry;
      }
    }
    return NullCommitEntry();
  }

  @Deprecated('No longer used by SyncServiceImpl. The push path '
      'does not prune commit-log entries — they are managed by '
      'AtCompactionJob. Scheduled for removal.')
  Future<void> removeCommitEntry(dynamic key, String atSign) async {
    atCommitLog ??=
        await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);
    await atCommitLog!.commitLogKeyStore.remove(key);
  }

  /// Sorts the commit entries in descending order.
  ///
  /// The CommitEntries with commitId 'null' comes before the commit entries with commitId
  int _compareCommitId(CommitEntry commitEntry1, CommitEntry commitEntry2) {
    if (commitEntry1.commitId == null && commitEntry2.commitId == null) {
      return 0;
    }
    if (commitEntry1.commitId == null && commitEntry2.commitId != null) {
      return -1;
    }
    if (commitEntry1.commitId != null && commitEntry2.commitId == null) {
      return 1;
    }
    return commitEntry2.commitId!.compareTo(commitEntry1.commitId!);
  }
}
