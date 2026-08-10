import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/atsign.dart';

/// Stores [AtKeys] in process memory.
///
/// This implementation is useful for tests and short-lived flows where the keys
/// have already been loaded or generated elsewhere. It does not encrypt,
/// serialize, or persist keys beyond the lifetime of this object.
class InMemoryAtKeysIo extends WrittenAtKeysIo {
  /// Keys are indexed by normalized [Atsign] (via `toAtsign()`), so the
  /// `String`-typed [read]/[write] and the [Atsign]-typed [flush] all resolve
  /// to the same entry.
  final Map<Atsign, AtKeys> _internal = {};

  /// Returns the keys for [atsign], or throws if nothing has been loaded into
  /// memory for that atsign.
  @override
  FutureOr<AtKeys> read(String atsign) {
    return _internal[atsign.toAtsign()] ??
        (throw AtKeysNotInMemoryException('$atsign not found in memory'));
  }

  /// Create-only, like every [WrittenAtKeysIo.write]: throws
  /// [AtKeysFileOverwriteException] when keys for [atsign] are already
  /// loaded. Use [flush] (or [update]) for later mutations.
  ///
  /// This double used to replace silently, which made it lie as a stand-in:
  /// code that double-wrote passed against memory and threw against the
  /// file store.
  @override
  Future<void> write(String atsign, AtKeys atKeys) async {
    final key = atsign.toAtsign();
    if (_internal.containsKey(key)) {
      throw AtKeysFileOverwriteException(
          'Keys for $atsign are already loaded; write is create-only — '
          'flush persists mutations');
    }
    _internal[key] = atKeys;
  }

  /// Literal mirror to write as there is no need to flush to memory.
  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    _internal[atsign.toAtsign()] = atKeys;
  }
}
