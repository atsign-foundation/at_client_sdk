import 'dart:async';

// Narrow src imports, not the public barrel: `at_auth.dart` carries the
// `dart:io` half of the package, so importing it here would drag `FileAtKeysIo`
// and the TLS probe into everything reachable from `at_auth_web.dart`.
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
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
