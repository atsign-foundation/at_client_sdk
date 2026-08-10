import 'package:at_client/src/client/at_client_spec.dart' show AtClient;

/// A per-client registry for an SDK-chosen era default.
///
/// The SDK resolves some defaults *per client* rather than per preference —
/// a preference object is routinely shared across atSigns, so resolving the
/// SDK's default *into* it would leak one client's resolution to another.
/// This registry keeps the association beside the client instead (an
/// [Expando]: the entry lives and dies with the client), which is the same
/// don't-write-to-the-shared-preference rule the crypto config's era
/// default was born with.
///
/// Extracted from `CryptoConfig`, which used to carry the registry as a
/// static inside the value type it stores. An instance is injectable and
/// resettable: production code uses the one its owner holds, and a test
/// can construct its own or [clear] a client's entry.
class EraDefaults<T extends Object> {
  final Expando<T> _byClient = Expando<T>('eraDefault');

  /// The era default [atClient] holds, or null when it was never given one.
  T? of(AtClient atClient) => _byClient[atClient];

  /// Gives [atClient] the era default [value], unless it already holds one.
  /// Idempotent — a re-used cached client keeps the value it was built
  /// with, so per-client state hanging off the value survives re-creation.
  void adoptIfAbsent(AtClient atClient, T value) {
    _byClient[atClient] ??= value;
  }

  /// Forgets [atClient]'s era default. For tests that rebuild a client's
  /// world; production code has no reason to un-adopt.
  void clear(AtClient atClient) {
    _byClient[atClient] = null;
  }
}
