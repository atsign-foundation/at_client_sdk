import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_commons/at_commons.dart' show AtKey;
import 'package:at_commons/at_builders.dart'
    show DeleteVerbBuilder, UpdateVerbBuilder;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('MintLock');

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
/// hands it here, ttl and all. The take/release is identical for both, and
/// two copies of it would be two chances for one to gain a fix the other
/// lacks.
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
  Future<T?> withLock<T>(AtKey lockKey, Future<T> Function() mint) async {
    if (!await _take(lockKey)) {
      _logger.info('Another enrollment holds $lockKey; re-reading rather than '
          'waiting for it');
      return null;
    }
    try {
      return await mint();
    } finally {
      await _release(lockKey);
    }
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

  Future<void> _release(AtKey lockKey) async {
    try {
      // Deleting an immutable record needs the force flag — the same property
      // that makes the lock an interlock also stops it being cleared by
      // accident.
      await atClient.getRemoteSecondary()!.executeVerb(
          DeleteVerbBuilder()
            ..atKey = lockKey
            ..force = true,
          sync: false);
    } catch (e) {
      // The ttl is the backstop, so a failed release costs a delay before the
      // next mint, never a lost key.
      _logger.info('Could not release $lockKey; it will expire on its own: $e');
    }
  }
}
