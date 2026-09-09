import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show parseCkConveyanceKey;
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

final _logger = AtSignLogger('ContentKeyEviction');

/// Drops a cached content key when this client observes its conveyance record
/// being deleted.
///
/// Deleting the `<ckKid>.__ck.<ckNs>@<owner>` record stops anyone unwrapping
/// that CK again, but a client that already unwrapped it holds the plaintext
/// key until it observes the deletion — so forward secrecy here is bounded by
/// resync reachability, and an offline device keeps reading.
///
/// Only `remoteToLocal` deletions count; a local delete has already evicted
/// through `CkManager`.
@experimental
class ContentKeyEviction extends SyncProgressListener {
  final ContentKeyCache cache;

  ContentKeyEviction(this.cache);

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    for (final keyInfo in syncProgress.keyInfoList ?? const <KeyInfo>[]) {
      if (keyInfo.syncDirection != SyncDirection.remoteToLocal ||
          keyInfo.commitOp != CommitOp.DELETE) {
        continue;
      }
      final conveyance = parse(keyInfo.key);
      if (conveyance == null) continue;
      // NOTE: the eviction scope comes from the key itself because the cache's
      // did too — every writer scopes an entry to `sharedWith ?? sharedBy`, so
      // this client's own atSign cannot serve as the scope.
      cache.evict(conveyance.nskeyOwner, conveyance.ckNs, conveyance.ckKid);
      _logger.info('Evicted content key ${conveyance.ckKid} for '
          '${conveyance.nskeyOwner}:${conveyance.ckNs} — its conveyance '
          'record was deleted, so data written under it is undecryptable from '
          'here on, by design');
    }
  }

  /// Splits a conveyance key string into the CK it carries, its namespace and
  /// its cache scope, or null when the key is not a conveyance record.
  @visibleForTesting
  static ({String nskeyOwner, String ckKid, String ckNs})? parse(String key) =>
      parseCkConveyanceKey(key);
}
