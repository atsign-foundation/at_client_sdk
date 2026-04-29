import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

/// Class contains all the util methods that perform CRUD operations on the commit log keystore.
class SyncUtil {
  static var logger = AtSignLogger('SyncUtil');

  final AtCommitLog atCommitLog;

  SyncUtil({required this.atCommitLog});

  Future<CommitEntry?> getCommitEntry(int sequenceNumber) async {
    return atCommitLog.getEntry(sequenceNumber);
  }

  Future<void> updateCommitEntry(
      CommitEntry commitEntry, int commitId) async {
    await atCommitLog.update(commitEntry, commitId);
  }

  Future<CommitEntry?> getLastSyncedEntry(String? regex) async {
    if (regex != null) {
      return atCommitLog.lastSyncedEntryWithRegex(regex);
    }
    return atCommitLog.lastSyncedEntry();
  }

  Future<List<CommitEntry>> getChangesSinceLastCommit(
      int? seqNum, String? regex) async {
    return (await atCommitLog.getChanges(seqNum, regex))
        .where((commitEntry) => !commitEntry.atKey!.startsWith('local:'))
        .toList();
  }

  //#TODO change return type to enum which says in sync, local ahead or server ahead
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

  Future<void> removeCommitEntry(dynamic key) async {
    await atCommitLog.commitLogKeyStore.remove(key);
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
