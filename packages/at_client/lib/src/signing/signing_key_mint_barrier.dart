import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;

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

/// The future a signer awaits before reading which keys may sign, or null
/// when nothing registered one — a client built without the PQ startup has
/// no mint in flight to wait for.
Future<void>? signingKeyMintSettled(AtClient client) => _pending[client];

/// Registers [settled] as [client]'s mint barrier. Called once per client
/// by the startup that owns the mint. [settled] must complete on every
/// path — a mint that failed, was stopped or was gated off included —
/// because everything that signs waits on it.
void registerSigningKeyMintBarrier(AtClient client, Future<void> settled) =>
    _pending[client] = settled;
