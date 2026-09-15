import 'dart:async';

import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';

import '../at_keys.dart' show AtKeys;
import 'package:at_commons/at_commons.dart';

/// Base type for reading [AtKeys]. Implemented by classes that read AtKeys
/// from different sources.
sealed class AtKeysIo {
  final passphraseCodec = const AtKeysPassphraseEnvelopeCodec();
  final assurance = const AtKeysAssurance();
  FutureOr<AtKeys> read(String atsign);
}

/// An interface that defines methods for AtKeys that can be written.
/// It can be implemented by classes that write AtKeys to different sources,
/// such as file system or keychain.
abstract class WrittenAtKeysIo extends AtKeysIo {
  /// Create-only initial persist (fresh onboard); implementations throw if
  /// the target already exists. Use [flush] to persist later mutations.
  //todo: futureOr & Atsign types
  Future write(String atsign, AtKeys atKeys);

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
  ///
  /// The default implementation throws: pre-existing [WrittenAtKeysIo]
  /// implementations compile unchanged but must override [flush] to
  /// support runtime persistence.
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    throw UnimplementedError(
        '$runtimeType does not implement flush(); override it to support '
        'runtime persistence');
  }

  /// Reads [atsign]'s keys, applies [mutate] to them, and persists the result
  /// — as **one** operation.
  ///
  /// This is what a caller adding key material should use, not a hand-rolled
  /// `read` → mutate → [flush]. Those three steps interleave: two of them
  /// running concurrently both read the same state, and the second [flush]
  /// presents a candidate missing the first's addition. [flush] is right to
  /// refuse it — nothing may be lost — so the outcome is a thrown assurance
  /// exception and one addition silently gone. A client's start does exactly
  /// this today, firing the namespace-key seeding and the conveyed-key filing
  /// as sibling unawaited tasks.
  ///
  /// Implementations backed by a lockable store take the lock across all three
  /// steps. The default here does not — it is read/mutate/flush — which is no
  /// worse than the hand-rolled form it replaces, and gives every store one
  /// call to serialise later.
  ///
  /// [mutate] receives the freshly-read [AtKeys] and mutates it in place. It
  /// returns whether anything changed: **false** abandons the write, which is
  /// how a caller that finds the material already there — re-delivery is the
  /// substrate's normal mode — avoids rewriting the store to say nothing.
  /// Throwing from it abandons the write too.
  ///
  /// **This never creates.** It is a read-modify-write of material that must
  /// already be there, and [read] throws when it is not — so an implementation
  /// that can observe its backing going away between the read and the write
  /// must refuse rather than write it back. For a keyfile that matters beyond
  /// tidiness: the file is the credential, deleting it is how a device is
  /// decommissioned, and putting it back defeats the delete.
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    final keys = await read(atsign.toString());
    if (await mutate(keys) == false) return;
    await flush(atsign, keys);
  }
}

/// An interface that defines methods for AtKeys that can be generated.
/// It can be implemented by classes that generate AtKeys using different methods,
/// such as secure element.
abstract class GeneratedAtKeysIo extends AtKeysIo {
  AtKeys generateKeys(String publicKeyId);
}

