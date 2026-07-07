import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/types.dart';
import 'package:at_commons/atsign.dart';

/// Stores [AtKeys] in process memory.
///
/// This implementation is useful for tests and short-lived flows where the keys
/// have already been loaded or generated elsewhere. It does not encrypt,
/// serialize, or persist keys beyond the lifetime of this object.
class InMemoryAtKeysIo extends WrittenAtKeysIo {
  /// Keys are indexed by normalized [Atsign] so callers can pass either raw
  /// string atSigns or [Atsign] values through the public methods.
  final Map<Atsign, AtKeys> _internal = {};

  /// Returns the keys for [atsign], or throws if nothing has been loaded into
  /// memory for that atSign.
  @override
  FutureOr<AtKeys> read(String atsign) {
    return _internal[atsign.toAtsign()] ??
        (throw AtKeysNotInMemoryException('$atsign not found in memory'));
  }

  /// Replaces any existing in-memory keys for [atsign].
  ///
  /// Prefer [append] when adding one key material entry to an existing in-memory
  /// key set. Use [write] when loading or replacing the complete [AtKeys] object.
  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    _internal[atsign.toAtsign()] = atKeys;
  }

  /// Adds [material] to the in-memory key set for [atsign].
  ///
  /// If no keys have been loaded yet, this creates a new [AtKeys] object for the
  /// atSign before adding the material.
  @override
  FutureOr<void> append(Atsign atsign, AtKeysMaterial material) {
    final atKeys = _internal.putIfAbsent(atsign, () => AtKeys(atsign: atsign));
    atKeys.addKey(material);
  }
}
