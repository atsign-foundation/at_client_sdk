import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';

/// Sync helpers that survive the commit-log-free client keystore.
///
/// The client→server push path drains `LocalSecondary`'s
/// [AtSyncQueue] directly, and the pull watermark is persisted in a
/// dedicated keystore key (`_lastReceivedServerCommitIdAtKey`), so
/// none of the old commit-log scan / back-write helpers remain. What
/// is left is the remote-stats commitId lookup and the static
/// should-this-key-ever-sync filter — neither touches a commit log.
class SyncUtil {
  static var logger = AtSignLogger('SyncUtil');

  SyncUtil();

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
}
