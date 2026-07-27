import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';

import '../at_keys.dart' show AtKeys;
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// Base type for reading [AtKeys]. Implemented by classes that read AtKeys
/// from different sources.
sealed class AtKeysIo {
  final passphraseCodec = const AtKeysPassphraseEnvelopeCodec();
  final assurance = const AtKeysAssurance();
  FutureOr<AtKeys> read(Atsign atsign);
}

/// An interface that defines methods for AtKeys that can be written.
/// It can be implemented by classes that write AtKeys to different sources,
/// such as file system or keychain.
abstract class WrittenAtKeysIo extends AtKeysIo {
  /// Create-only initial persist (fresh onboard); implementations throw if
  /// the target already exists. Use [flush] to persist later mutations.
  FutureOr<void> write(Atsign atsign, AtKeys atKeys);

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
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys);
}

abstract class InMemoryAtKeysIo extends AtKeysIo {
  FutureOr<void> write(Atsign atsign, AtKeys atKeys);
  FutureOr<AtKeysMaterial> append(Atsign atsign, AtKeysMaterial key);
  FutureOr<AtKeysMaterial> retire(Atsign atsign, AtKeysMaterial key);
  FutureOr<void> dispose();
}
