import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:meta/meta.dart' show visibleForTesting;

// A leaf library on purpose: it imports the AtClient spec and nothing else.
// The signers that read the barrier and the startup that registers it sit on
// opposite sides of an import chain (mixins -> bootstrap -> signing ->
// mixins), so the handoff lives where neither side has to import the other.

/// The per-client barrier between "this client is minting its own signing
/// keys" and "this client's signers read what may sign".
///
/// A client's startup mints signing keys concurrently with whatever the
/// application does next, and publishing a minted key withdraws the
/// authentication key from the advertisement before the keyfile holds the
/// minted one. A signer reading the keyfile in that window finds nothing,
/// falls back to the authentication key, and produces an envelope the
/// just-published advertisement no longer names a key for — nothing can
/// verify it. Waiting on the registered future closes the window.
///
/// Keyed on the [AtClient] instance rather than the atSign: two clients of
/// one atSign mint independently, and each waits only for its own mint.
final Expando<Future<void>> _pending = Expando('signing-key mint settled');

/// How long a signer waits for the mint before signing with what the keyfile
/// already holds.
///
/// The barrier is settled by the mint step and, as a backstop, by the
/// startup's `finally` — so it completes on every path the startup can
/// *return* by. What neither covers is a startup that never returns: a step
/// before the mint that blocks leaves the barrier unsettled for the life of
/// the process, and an unbounded wait then turns that into a deadlock in
/// everything that signs, silently and with nothing in the log.
///
/// Measured: a `collectConveyedKeys` sweep whose remote scan did not return
/// held the barrier open, and an `at_activate approve` waiting to sign the
/// envelope it had just sealed never terminated — through a six-minute test
/// timeout and a seven-minute manual bound alike.
///
/// Generous, because the window this closes is a real one and signing early
/// produces an envelope nothing can verify. The point is not to be tight; it
/// is that the failure is bounded and says so.
@visibleForTesting
Duration signingKeyMintWait = const Duration(seconds: 45);

/// The future a signer awaits before reading which keys may sign, or null
/// when nothing registered one — a client built without the PQ startup has
/// no mint in flight to wait for.
Future<void>? signingKeyMintSettled(AtClient client) => _pending[client];

/// Waits for [client]'s mint to settle, bounded by [signingKeyMintWait].
///
/// Returns null when there is nothing to wait for or the mint settled, and
/// the elapsed bound when it did not — which means the startup is stuck
/// before the mint step and the caller should sign with what the keyfile
/// already holds rather than wait for a mint that is not coming.
///
/// The bound lives here, with the barrier, because it is the barrier's own
/// policy: every signer waits the same way, and a signer that invented its
/// own would be a second answer to the same question.
Future<Duration?> awaitSigningKeyMint(AtClient client) async {
  final settled = _pending[client];
  if (settled == null) return null;
  try {
    await settled.timeout(signingKeyMintWait);
    return null;
  } on TimeoutException {
    return signingKeyMintWait;
  }
}

/// Registers [settled] as [client]'s mint barrier. Called once per client
/// by the startup that owns the mint. [settled] must complete on every
/// path — a mint that failed, was stopped or was gated off included —
/// because everything that signs waits on it.
void registerSigningKeyMintBarrier(AtClient client, Future<void> settled) =>
    _pending[client] = settled;
