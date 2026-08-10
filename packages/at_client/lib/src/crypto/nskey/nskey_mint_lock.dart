import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_commons/at_commons.dart' show AtKey;
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_commons/at_builders.dart'
    show DeleteVerbBuilder, UpdateVerbBuilder;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('NskeyMintLock');

/// Serialises minting and rotating a namespace key between an atSign's own
/// enrollments.
///
/// The advertisement itself is **mutable** — rotation has to overwrite it —
/// so immutability cannot serve as the interlock there. It moves here instead:
/// a short-ttl immutable self key whose creation the atServer refuses to
/// repeat.
///
/// The atomicity is the atServer's, and only the atServer's. `_take` writes
/// remote-first for exactly that reason: a local-first put would succeed on
/// both enrollments, each believing it had won, and collide only at sync —
/// long after both had minted and one had overwritten the other's
/// advertisement.
@experimental
class NskeyMintLock {
  final AtClient atClient;

  /// How long the lock survives unreleased. It is a crash backstop, not a
  /// budget: a holder that dies mid-mint must not block its own atSign
  /// forever. Long enough that an ordinary mint never races its own
  /// expiry.
  final Duration ttl;

  const NskeyMintLock(this.atClient, {this.ttl = const Duration(minutes: 2)});

  AtKey keyFor(String owner, String namespace) =>
      nskeyMintLockKey(owner, namespace, ttl: ttl);

  /// Runs [mint] holding the lock, and returns its result.
  ///
  /// Returns null when another of this atSign's enrollments holds the lock.
  /// The loser deliberately does **not** wait: whatever the winner is doing
  /// ends with an advertisement published, so re-reading is both cheaper and
  /// more useful than queueing behind it — and if the winner has crashed,
  /// waiting would mean waiting out the ttl for nothing.
  Future<T?> withLock<T>(
      String owner, String namespace, Future<T> Function() mint) async {
    if (!await _take(owner, namespace)) {
      _logger.info('Another enrollment is minting $owner:$namespace; '
          're-reading rather than waiting for it');
      return null;
    }
    try {
      return await mint();
    } finally {
      await _release(owner, namespace);
    }
  }

  Future<bool> _take(String owner, String namespace) async {
    try {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = keyFor(owner, namespace)
            ..value = DateTime.now().toUtc().toIso8601String(),
          sync: false);
      return true;
    } catch (e) {
      // The atServer refuses a second write to an immutable record, which is
      // precisely the contention signal. Anything else that stops us taking
      // the lock is equally a reason not to mint.
      _logger.finer('Could not take the mint lock for $owner:$namespace: $e');
      return false;
    }
  }

  Future<void> _release(String owner, String namespace) async {
    try {
      // Deleting an immutable record needs the force flag — the same property
      // that makes the lock an interlock also stops it being cleared by
      // accident.
      await atClient.getRemoteSecondary()!.executeVerb(
          DeleteVerbBuilder()
            ..atKey = keyFor(owner, namespace)
            ..force = true,
          sync: false);
    } catch (e) {
      // The ttl is the backstop, so a failed release costs a delay before the
      // next mint, never a lost key.
      _logger.info('Could not release the mint lock for $owner:$namespace; it '
          'will expire on its own: $e');
    }
  }
}
