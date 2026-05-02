// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

// HiveKeystore isn't exported from the package barrel of
// at_persistence_secondary_server. This extension adds the
// `nextExpiryAt()` hook the at_client side needs to drive its
// event-driven expiry timer (see `AtClientImpl._armExpiryTimer`).
// The user's parallel persistence project will eventually fold
// `nextExpiryAt()` into the keystore proper as a public method, at
// which point this extension is deprecated and removed (see plan
// "Migration / rollback").
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';

/// Adds an event-driven expiry hook to [HiveKeystore], computed from
/// the existing in-memory `_expiryKeysCache` (reachable via
/// [HiveKeystore.getExpiryKeysCache], `@visibleForTesting`-marked but
/// public at the language level).
extension HiveKeystoreExpiryExt on HiveKeystore {
  /// Earliest `expiresAt` across all keys currently tracked in the
  /// keystore's expiry-keys cache, or `null` if no key carries a TTL.
  ///
  /// O(n) over the cache size, where n is the number of TTL'd keys
  /// (NOT the total number of records — keys without TTL are not in
  /// the cache).
  ///
  /// Ignores `availableAt` — TTB is about visibility / not-yet-born
  /// records, while this hook drives the *deletion* sweep.
  DateTime? nextExpiryAt() {
    DateTime? earliest;
    for (final entry in getExpiryKeysCache().values) {
      final exp = entry['expiresAt'];
      if (exp == null) continue;
      if (earliest == null || exp.isBefore(earliest)) earliest = exp;
    }
    return earliest;
  }
}
