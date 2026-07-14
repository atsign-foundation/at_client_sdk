import 'dart:async';

import 'package:at_auth/at_auth.dart';
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
  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    _internal[atsign.toAtsign()] = atKeys;
  }

  /// Literal mirror to write as there is no need to flush to memory.
  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    _internal[atsign.toAtsign()] = atKeys;
  }
}
