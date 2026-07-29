import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

/// Base type for reading and creating [AtKeys], backed by a file, a keychain,
/// process memory, or anything else.
///
/// Every method takes a normalized [Atsign] rather than a `String`. Callers
/// normalize once at the boundary with `toAtsign()`; implementations can then
/// treat the value as canonical, so a keyfile can never be created under one
/// spelling of an atsign and looked up under another. (`Atsign` is a subtype of
/// `String`, so an implementation may still widen a parameter to `String` — but
/// nothing in this package does, and new code should not.)
///
/// [write] lives here rather than on [WrittenAtKeysIo] so that a caller holding
/// a plain `AtKeysIo` can persist a fresh keyset without switching on the
/// subtype. The tradeoff is deliberate: there is no read-only implementation.
sealed class AtKeysIo {
  final passphraseCodec = const AtKeysPassphraseEnvelopeCodec();
  final assurance = const AtKeysAssurance();

  FutureOr<AtKeys> read(Atsign atsign);

  /// Create-only initial persist (fresh onboard); implementations throw if
  /// the target already exists. Use [WrittenAtKeysIo.flush] to persist later
  /// mutations of a durable store.
  FutureOr<void> write(Atsign atsign, AtKeys atKeys);
}

/// An interface that defines methods for AtKeys held in durable storage —
/// a file system or keychain — which can be rewritten in place.
abstract class WrittenAtKeysIo extends AtKeysIo {
  /// Persists [atKeys] as the complete new state for [atsign].
  ///
  /// This is the runtime counterpart to [write]: mutate the in-memory
  /// [AtKeys] (e.g. [AtKeys.addKey]), then flush the whole object.
  /// Implementations backed by durable storage must not lose data: when a
  /// target already exists, validate that everything in it is preserved in
  /// [atKeys] (see [AtKeysAssurance.validateMapUpdate]), then rewrite. When
  /// no target exists, flush creates it — there is nothing to lose.
  ///
  /// The never-lose contract applies to stores of bootstrap key material
  /// (the `.atKeys` file, keychain). A store holding rotating or evictable
  /// material defines its own retention policy — deletion there is a
  /// feature (forward secrecy), not data loss.
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys);
}

/// An interface for AtKeys held only in process memory, for tests and
/// short-lived flows where the keys were loaded or generated elsewhere.
///
/// Mutation is per-material ([append]/[retire]) rather than whole-state: an
/// in-memory store holds rotating material and defines its own retention
/// policy, so it has no [WrittenAtKeysIo.flush] and its never-lose contract
/// does not apply.
abstract class InMemoryAtKeysIo extends AtKeysIo {
  FutureOr<AtKeysMaterial> append(Atsign atsign, AtKeysMaterial key);
  FutureOr<AtKeysMaterial> retire(Atsign atsign, AtKeysMaterial key);
  FutureOr<void> dispose();
}
