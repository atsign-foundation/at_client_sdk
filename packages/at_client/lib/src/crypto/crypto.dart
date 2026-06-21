import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_commons.dart';

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
      : defaultProviderId = 'legacy',
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

  /// Encrypt plaintext [value] for [atKey], returning the wire ciphertext.
  ///
  /// The provider sets `atKey.metadata.appMetadata` (at least its own [id]) and
  /// `atKey.metadata.isEncrypted` as part of encrypting. [context] gives access
  /// to the client and key material needed to complete the operation.
  Future<String> encrypt(CryptoContext context, AtKey atKey, String value);

  /// Decrypt wire ciphertext [value] for [atKey], returning the plaintext.
  /// Routing hints are read from `atKey.metadata.appMetadata`.
  Future<String> decrypt(CryptoContext context, AtKey atKey, String value);
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
