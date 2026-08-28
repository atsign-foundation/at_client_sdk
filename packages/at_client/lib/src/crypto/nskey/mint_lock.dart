import 'dart:async' show Completer;

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
}

/// Serialises minting a key record between an atSign's own enrollments.
///
/// The records this guards are **mutable** — the nskey advertisement because
/// rotation has to overwrite it, the signing root because it is an ordinary
/// signing key — so immutability cannot serve as the interlock on the record
/// itself. It
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

  /// Mints for `(owner, namespace)` running **against this `MintLock` instance
  /// right now**, keyed by lock record.
  ///
  /// ⚠️ **Instance, not process** — this said "in this process" until
  /// 2026-08-27 and that is wider than the code. A `MintLock` is built per
  /// [PublishedNskeyKeyRing], and rings are constructed in several places, two
  /// of them inline per call. Callers that do not share a ring are not guarded
  /// against each other. It covers the case it was built for because a
  /// client's PQ startup and `AtClient.ensureReachable` both reach the
  /// bootstrap's single ring — which is a fact about that wiring, not a
  /// property of this map, and worth re-checking if either moves.
  ///
  /// The wire lock cannot express this. Its value is the enrolment id — an
  /// identity, not an instance — so two racers of the SAME enrolment each read
  /// it back, each see their own id, and each conclude they hold it. Measured
  /// live 2026-08-27: two advertisements 7.5ms apart carrying different key
  /// material, the second overwriting the first, both conveyed. A peer that
  /// fetched between them holds a generation whose private the owner may have
  /// replaced.
  ///
  /// ⚠️ **Deliberately NOT fixed by making the wire token per-instance.** That
  /// would break the case [_isOwnLock] exists for: a client restarting inside
  /// the cooldown is a *new* instance and would no longer recognise the lock
  /// it took a moment ago, so it would take the loser path and refuse to
  /// mint for the rest of the ttl. The distinction that matters is not "which
  /// instance" but "is one already in flight here", and only this process can
  /// answer that.
  final Map<String, Future<void>> _inFlight = {};

  MintLock(this.atClient);

  /// Runs [mint] holding [lockKey], and returns its result.
  ///
  /// Returns null when the lock is already held — so a caller whose [mint]
  /// can itself return null should return something non-null from it, or the
  /// two answers become one.
  ///
  /// ⚠️ **"Held" is not the same as "another enrollment is minting".** The
  /// winner never releases, so a client that took the lock and exited before
  /// publishing loses to its OWN token on its next start, and keeps losing for
  /// the rest of the ttl — with nothing in flight anywhere. **How long that
  /// lasts is per-lock, deliberately**: `mintLockTtl` is two minutes and the
  /// nskey path can afford it because it opts in below, while
  /// `signingRootMintLockTtl` is fifteen seconds precisely because the root
  /// path does not. Unless [ownLockIsNotContention] is set, nothing here reads the
  /// lock's value, so this cannot tell the two apart and does not claim to.
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
  /// [ownLockIsNotContention] lets a caller whose critical section is
  /// **idempotent** proceed when the lock it meets is one this same enrollment
  /// took earlier in the cooldown.
  ///
  /// Off by default, and that default is the important half. The cooldown
  /// deliberately binds **rotation** — a rotation is not idempotent, it
  /// overwrites on purpose, and rate-limiting it is the point of holding the
  /// lock for the full ttl rather than releasing it. A caller that opts in
  /// must be one that reads what is published before writing, so meeting its
  /// own token costs a re-read rather than a second key.
  Future<T?> withLock<T>(
      AtKey lockKey, Future<T> Function(MintLease lease) mint,
      {bool ownLockIsNotContention = false}) async {
    // A mint for this key is already running HERE. Wait for it and then
    // decline, so the caller takes its ordinary loser path: it re-reads what
    // is published and adopts. Declining rather than returning the winner's
    // result keeps one meaning for a null — "you did not mint" — and the
    // re-read is what every caller already does.
    final inFlightKey = lockKey.toString();
    final running = _inFlight[inFlightKey];
    if (running != null) {
      _logger.info('A mint for $lockKey is already in flight in this process; '
          'waiting for it rather than racing it, then re-reading');
      await running;
      return null;
    }

    final ttlMillis = lockKey.metadata.ttl;
    if (ttlMillis == null || ttlMillis <= 0) {
      // Refused rather than defaulted. Nothing deletes this record now, so a
      // lock with no ttl is not a lock that releases late — it is one that
      // never releases, and it would block its atSign's minting for good.
      throw ArgumentError.value(
          ttlMillis,
          'lockKey.metadata.ttl',
          'a mint lock needs a ttl: it is released by expiry and by nothing '
              'else, so without one $lockKey would block minting permanently');
    }
    final done = Completer<void>();
    _inFlight[inFlightKey] = done.future;
    try {
      // Stamped before the request goes out — see [MintLease.expiresAt].
      final leaseFrom = DateTime.now();
      if (!await _take(lockKey,
          ownLockIsNotContention: ownLockIsNotContention)) {
        // Deliberately not "another enrollment holds it". Where the caller
        // did not opt in, nothing read the lock's value, so whose it is was
        // never established — and one of the cases is this same enrollment's
        // previous run, still inside the cooldown, with nobody minting at
        // all. Naming a second enrollment there sends a reader looking for a
        // process that does not exist.
        _logger.info('$lockKey is already held; re-reading rather than '
            'waiting for it. Whether the holder is another enrollment or '
            'this one from an earlier run was not established');
        return null;
      }
      return await mint(
          MintLease(leaseFrom.add(Duration(milliseconds: ttlMillis))));
    } finally {
      // Released only once the mint has finished — including its publish — so
      // a waiter that wakes here re-reads an advertisement that is already on
      // the atServer rather than the absence that made it race.
      _inFlight.remove(inFlightKey);
      done.complete();
    }
  }

  /// This client's identity in a lock record.
  ///
  /// The enrollment is the grain the lock is about — the contention it exists
  /// to resolve is between an atSign's own enrollments — so an enrollment
  /// meeting its own token is not contention. A client with no enrollment id
  /// authenticates as the owner and there is only ever one of those, so the
  /// sentinel below is equally distinct from any enrollment's id.
  String get _holder => atClient.enrollmentId ?? 'primary';

  Future<bool> _take(AtKey lockKey,
      {required bool ownLockIsNotContention}) async {
    try {
      await atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = lockKey
        ..value = _holder
        // A lock lives for its ttl and is never read by another device, so a
        // commit entry for it buys nothing and costs everything that syncs:
        // every client pulls the record down, waits out the same ttl, and then
        // reclaims it locally. Asking the atServer not to record the write
        // keeps the interlock — the refusal of a second write to an immutable
        // record is what the lock IS, and that is unaffected.
        ..noCommit = true);
      return true;
    } catch (e) {
      // The atServer refuses a second write to an immutable record, which is
      // precisely the contention signal. Anything else that stops us taking
      // the lock is equally a reason not to mint.
      _logger.finer('Could not take $lockKey: $e');
      if (!ownLockIsNotContention) return false;
      return _isOwnLock(lockKey);
    }
  }

  /// Whether the lock that refused us is one **this enrollment** already holds.
  ///
  /// The winner never releases — the ttl does — so for the whole cooldown a
  /// client that mints and then re-enters loses the election to *itself*, and
  /// takes the loser path: it re-reads the advertisement rather than
  /// reconciling, and a loser is not guaranteed to hold the private half of
  /// what it reads. At `mintLockTtl`'s two minutes — the value on the lock
  /// every caller that reaches this method takes — that window covers an
  /// ordinary restart, so the case is not exotic.
  ///
  /// Proceeding here is safe because the critical section is idempotent: every
  /// caller reads what is published before minting, so an owner re-entering
  /// returns the existing record rather than rotating it out from under a peer
  /// that already fetched it. What the cooldown protects against is a *second
  /// enrollment* minting, and that is unchanged.
  ///
  /// A read that cannot say whose lock it is answers false — the lock's whole
  /// purpose is to refuse when ownership is unclear.
  Future<bool> _isOwnLock(AtKey lockKey) async {
    try {
      final held = await atClient
          .getRemoteSecondary()!
          .executeCommand('llookup:${lockKey.toString()}\n', auth: true);
      if (held == null || !held.startsWith('data:')) return false;
      final value = held.replaceFirst('data:', '').trim();
      if (value != _holder) return false;
      _logger.info('$lockKey is this enrollment\'s own lock, taken earlier in '
          'its cooldown — proceeding rather than treating ourselves as a '
          'loser');
      return true;
    } catch (e) {
      _logger.finer('Could not read $lockKey to check ownership: $e');
      return false;
    }
  }
}
