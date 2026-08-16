import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_commons/at_commons.dart' show AtKey;
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('MintLock');

/// The window in which the winner of an election may still act.
///
/// The winner carries this into its critical section and refuses to publish
/// once it is spent. Without it the "only one enrollment eventually mints"
/// requirement fails even with everything else correct: the election bounds
/// when the enrollments *attempt*, not how long the winner *takes*, so a
/// holder that overran the ttl would publish on top of the enrollment that
/// legitimately won the next one.
class MintLease {
  /// When this lease stops being valid.
  ///
  /// Stamped from **before** the take was issued, never after. The atServer
  /// starts the ttl when it stores the record, which is at or after the moment
  /// this client sent the request — so a deadline taken from the send makes
  /// the client give up slightly EARLY, while one taken from the reply would
  /// have it believe it still held a lock the atServer had already released.
  /// Only one of those errs safely.
  ///
  /// Not a clock comparison between two machines: the client stamps and reads
  /// this against its own clock throughout, and the atServer's ttl is the
  /// separate, authoritative bound.
  final DateTime expiresAt;

  const MintLease(this.expiresAt);

  /// Whether the lease has run out, so nothing further may be published under
  /// it.
  bool get isSpent => !DateTime.now().isBefore(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());
}

/// Serialises minting a key record between an atSign's own enrollments.
///
/// The records this guards are **mutable** — the nskey advertisement because
/// rotation has to overwrite it, the signing root because
/// `docs/projects/pq/decisions.md` 101 made the root an ordinary signing key —
/// so immutability cannot serve as the interlock on the record itself. It
/// moves here instead: a short-ttl immutable self key whose creation the
/// atServer refuses to repeat.
///
/// The atomicity is the atServer's, and only the atServer's. [_take] writes
/// remote-first for exactly that reason: a local-first put would succeed on
/// both enrollments, each believing it had won, and collide only at sync —
/// long after both had minted and one had overwritten the other's record.
///
/// **One mechanism, and the key says what is locked.** Each record composes
/// its own lock key — `nskeyMintLockKey`, `pqSigningRootMintLockKey` — and
/// hands it here, ttl and all. The take is identical for both, and two copies
/// of it would be two chances for one to gain a fix the other lacks.
///
/// ⚠️ **A lock is a protocol, not a guarantee.** A refused immutable create is
/// an absolute answer from the atServer about one record; this is a window
/// narrowed to the ttl. Every caller therefore still reconciles what it holds
/// against what is actually published, rather than trusting that holding the
/// lock made it the only writer.
@experimental
class MintLock {
  final AtClient atClient;

  const MintLock(this.atClient);

  /// Runs [mint] holding [lockKey], and returns its result.
  ///
  /// Returns null when another of this atSign's enrollments holds the lock —
  /// so a caller whose [mint] can itself return null should return something
  /// non-null from it, or the two answers become one.
  ///
  /// The loser deliberately does **not** wait: whatever the winner is doing
  /// ends with a record published, so re-reading is both cheaper and more
  /// useful than queueing behind it — and if the winner has crashed, waiting
  /// would mean waiting out the ttl for nothing.
  ///
  /// **The winner does not release the lock; the ttl does.** Holding it for
  /// the full ttl means "an election happened recently, do not hold another
  /// one" — the only case where a second election is wanted inside that window
  /// is the winner having failed, which is exactly what the ttl bounds, so in
  /// the success case the cooldown costs nothing. Deleting on the way out cost
  /// something real: a holder finishing late deleted its *successor's* lock,
  /// because the delete forced past an immutable record without checking it
  /// still owned the one it was removing. There is no such window to close now
  /// — there is no delete.
  ///
  /// ⚠️ Correct only against an atServer that stops refusing a create once the
  /// record has expired; an older one keeps refusing well past the ttl, which
  /// would make the cooldown effectively permanent.
  Future<T?> withLock<T>(
      AtKey lockKey, Future<T> Function(MintLease lease) mint) async {
    final ttlMillis = lockKey.metadata.ttl;
    if (ttlMillis == null || ttlMillis <= 0) {
      // Refused rather than defaulted. Nothing deletes this record now, so a
      // lock with no ttl is not a lock that releases late — it is one that
      // never releases, and it would block its atSign's minting for good.
      throw ArgumentError.value(ttlMillis, 'lockKey.metadata.ttl',
          'a mint lock needs a ttl: it is released by expiry and by nothing '
          'else, so without one $lockKey would block minting permanently');
    }
    // Stamped before the request goes out — see [MintLease.expiresAt].
    final leaseFrom = DateTime.now();
    if (!await _take(lockKey)) {
      _logger.info('Another enrollment holds $lockKey; re-reading rather than '
          'waiting for it');
      return null;
    }
    return mint(MintLease(leaseFrom.add(Duration(milliseconds: ttlMillis))));
  }

  Future<bool> _take(AtKey lockKey) async {
    try {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = lockKey
            ..value = DateTime.now().toUtc().toIso8601String(),
          sync: false);
      return true;
    } catch (e) {
      // The atServer refuses a second write to an immutable record, which is
      // precisely the contention signal. Anything else that stops us taking
      // the lock is equally a reason not to mint.
      _logger.finer('Could not take $lockKey: $e');
      return false;
    }
  }
}
