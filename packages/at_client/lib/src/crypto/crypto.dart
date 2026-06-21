import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_commons.dart';

/// The id of the built-in legacy (pre-pluggable) encryption scheme — the
/// default provider and the fallback for records with no `appMetadata`.
const String legacyCryptoProviderId = 'legacy';

/// Selects and configures the crypto providers for an [AtClient].
class CryptoConfig {
  /// Provider used when an [AtKey] carries no `appMetadata.providerId`.
  final String defaultProviderId;

  /// Provider instances registered with the client at construction.
  ///
  /// Providers are stateless, so an instance is normally safe to share. Supply
  /// a fresh instance per atSign only if your provider holds per-atSign state —
  /// the same instance is registered against each client that reuses this
  /// preference.
  final List<CryptoProvider> providers;

  const CryptoConfig({
    required this.defaultProviderId,
    this.providers = const [],
  });

  /// Legacy-only — the default for un-migrated apps.
  const CryptoConfig.legacy()
      : defaultProviderId = legacyCryptoProviderId,
        providers = const [];
}

/// What a [CryptoProvider] is handed per operation.
class CryptoContext {
  /// The fully-wired client. A provider uses it to fetch whatever it needs to
  /// complete an operation — a recipient's public key, a shared key, a
  /// namespace key from the secondary, etc. The current atSign is
  /// `atClient.getCurrentAtSign()`.
  ///
  /// This is the only field today. The planned `WritableAtKeys` holder — an
  /// `AtKeys` subclass letting providers read/stash/persist key material — is
  /// added here alongside its first consumer in the key-management workstream,
  /// at which point providers move off the client for keys.
  final AtClient atClient;

  const CryptoContext({required this.atClient});
}

/// The contract every encryption scheme implements. The SDK routes each
/// [AtKey] to a provider by its `appMetadata.providerId`.
///
/// Providers are **stateless**: everything they need is handed in per call via
/// [context] (the client) and [atKey] (the record and its metadata), so a
/// single instance is safely shared across atSigns.
abstract class CryptoProvider {
  /// Stable wire id, stamped into `appMetadata.providerId`.
  String get id;

  /// Encrypt [plaintext] for [atKey], returning the wire ciphertext.
  ///
  /// The SDK owns routing metadata: after this returns it stamps
  /// `atKey.metadata.appMetadata.providerId` (to this provider's [id]) and sets
  /// `isEncrypted`, so you can't accidentally break read-routing. To carry
  /// per-record data you'll need on [decrypt] (an IV, a key id, a format
  /// version, …), set `atKey.metadata.appMetadata` with those entries in
  /// [AppMetadata.additional]; they travel with the record (as atServer-visible
  /// plaintext metadata) and are readable on [decrypt].
  ///
  /// [plaintext] is opaque: for binary records it is a `Base2e15`-encoded
  /// string, not human-readable text — treat it as bytes, don't assume UTF-8.
  /// [context] gives access to the client (and, later, key material). Throw an
  /// [AtException] subclass (e.g. [AtEncryptionException]) on failure so the SDK
  /// can chain diagnostics.
  Future<String> encrypt(CryptoContext context, AtKey atKey, String plaintext);

  /// Decrypt wire [ciphertext] for [atKey], returning the plaintext.
  ///
  /// Read any per-record data you stored on [encrypt] from
  /// `atKey.metadata.appMetadata.additional`. The returned plaintext is opaque
  /// (a `Base2e15`-encoded string for binary records). Throw an [AtException]
  /// subclass (e.g. [AtDecryptionException]) on failure.
  Future<String> decrypt(CryptoContext context, AtKey atKey, String ciphertext);
}

/// Per-[AtClient] registry of [CryptoProvider]s, keyed by [CryptoProvider.id].
class CryptoRegistry {
  final Map<String, CryptoProvider> _providers = <String, CryptoProvider>{};

  /// Registers [provider] under its [CryptoProvider.id]. Throws [ArgumentError]
  /// if that id is already registered, unless [replace] is true.
  void register(CryptoProvider provider, {bool replace = false}) {
    if (!replace && _providers.containsKey(provider.id)) {
      throw ArgumentError.value(
        provider.id,
        'provider.id',
        'Crypto provider id is already registered. '
            'Pass replace: true to replace it intentionally.',
      );
    }
    _providers[provider.id] = provider;
  }

  /// Look up [id], or throw [CryptoProviderNotRegistered] if absent.
  ///
  /// [lookupReason] is woven into the not-registered error to aid diagnosis —
  /// typically the operation that triggered the lookup (e.g. `'put'`).
  CryptoProvider lookup(String id, {String lookupReason = 'none'}) {
    final provider = _providers[id];
    if (provider == null) {
      throw CryptoProviderNotRegistered(
        _notRegisteredMessage(id, lookupReason: lookupReason),
      );
    }
    return provider;
  }

  /// Whether a provider with [id] is registered.
  bool contains(String id) => _providers.containsKey(id);

  /// The ids of all currently registered providers.
  List<String> get registeredProviderIds =>
      _providers.keys.toList(growable: false);

  String _notRegisteredMessage(String id, {String lookupReason = 'none'}) {
    final ids = registeredProviderIds;
    final registered = ids.isEmpty ? 'none' : ids.join(', ');
    return 'Crypto provider "$id" is not registered. '
        'Lookup reason: $lookupReason. '
        'Registered providers: $registered. '
        'Add it to AtClientPreference.crypto.providers.';
  }
}
