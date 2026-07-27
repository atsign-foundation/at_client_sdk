import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/atsign.dart';

/// Stores [AtKeys] in process memory.
///
/// This implementation is useful for tests and short-lived flows where the keys
/// have already been loaded or generated elsewhere. It does not encrypt,
/// serialize, or persist keys beyond the lifetime of this object.
class EphemeralAtKeysIo extends InMemoryAtKeysIo {
  /// Keys are indexed by normalized [Atsign] (via `toAtsign()`), so the
  /// `String`-typed [read]/[write] and the [Atsign]-typed [append]/[retire]/
  /// [flush] all resolve to the same entry.
  final Map<Atsign, AtKeys> _internal = {};

  /// Returns the keys for [atsign], or throws if nothing has been loaded into
  /// memory for that atsign.
  @override
  FutureOr<AtKeys> read(String atsign) => _requireLoaded(atsign.toAtsign());

  /// Replaces any existing in-memory keys for [atsign].
  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    _internal[atsign.toAtsign()] = atKeys;
  }

  /// Adds a single [key] to the keys already loaded for [atsign] and returns
  /// it. Throws if nothing has been loaded for that atsign.
  @override
  FutureOr<AtKeysMaterial> append(Atsign atsign, AtKeysMaterial key) {
    _requireLoaded(atsign).addKey(key);
    return key;
  }

  /// Retires every material sharing `key.keyId` on the keys loaded for
  /// [atsign], returning the retired counterpart of [key].
  ///
  /// Key material is retired, never dropped (see [AtKeys.retireKey]) — retiring
  /// is `AtKeys`'s delete operation, so `remove` here honours that invariant
  /// rather than deleting bytes. Note [AtKeys.retireKey] is `keyId`-wide: it
  /// retires all parts of the keyId, not just the part [key] names. Throws if
  /// nothing has been loaded for [atsign] or the keyId is unknown.
  @override
  FutureOr<AtKeysMaterial> retire(Atsign atsign, AtKeysMaterial key) {
    final atKeys = _requireLoaded(atsign);
    atKeys.retireKey(key.keyId);
    return atKeys.getKey(key.keyId, key.keyPartType) ?? key;
  }

  /// Drops every atsign's keys from memory.
  @override
  FutureOr<void> dispose() {
    _internal.clear();
  }

  AtKeys _requireLoaded(Atsign atsign) =>
      _internal[atsign] ??
      (throw AtKeysNotInMemoryException('$atsign not found in memory'));
}
