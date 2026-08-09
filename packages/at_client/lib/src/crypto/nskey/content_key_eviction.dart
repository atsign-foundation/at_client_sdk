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
/// **The eviction trigger for coarse forward secrecy.** Deleting the
/// `<ckKid>.__ck.<ckNs>@<owner>` record stops anyone unwrapping that CK
/// *again*, but says nothing about the clients that already did — they hold the
/// plaintext key in their own caches and would go on reading data the deletion
/// was meant to close off. Sync carries the deletion to every client, and this
/// turns arrival into eviction, which is what makes forward secrecy a
/// fleet-wide property rather than a property of the deleting client alone.
///
/// It is therefore bounded by eviction **reachability**: a client that never
/// resyncs keeps its copy, and an offline device is the residual this design
/// names rather than solves.
///
/// Only `remoteToLocal` deletions count. A local delete has already evicted
/// through `CkManager` — reacting to its own push back would be harmless but
/// would also mean this had to be correct about a case it never sees.
@experimental
class ContentKeyEviction extends SyncProgressListener {
  final ContentKeyCache cache;

  /// This client's atSign, which is the CK cache's scope for **every** record
  /// this listener sees: a self conveyance is `…@alice` with no recipient, and
  /// an inbound one is `@alice:…@bob` — in both cases the nskey that opened it
  /// is alice's, and that is how `ContentKeyCache` keyed it.
  final String atSign;

  ContentKeyEviction(this.cache, this.atSign);

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    for (final keyInfo in syncProgress.keyInfoList ?? const <KeyInfo>[]) {
      if (keyInfo.syncDirection != SyncDirection.remoteToLocal ||
          keyInfo.commitOp != CommitOp.DELETE) {
        continue;
      }
      final conveyance = parse(keyInfo.key);
      if (conveyance == null) continue;
      cache.evict(atSign, conveyance.ckNs, conveyance.ckKid);
      _logger.info('Evicted content key ${conveyance.ckKid} for '
          '$atSign:${conveyance.ckNs} — its conveyance record was deleted, so '
          'data written under it is undecryptable from here on, by design');
    }
  }

  /// Splits a conveyance key string into the CK it carries and the namespace
  /// that CK lives in — see [parseCkConveyanceKey], which owns the format
  /// beside its builder.
  @visibleForTesting
  static ({String ckKid, String ckNs})? parse(String key) =>
      parseCkConveyanceKey(key);
}
