import 'dart:async';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_commons.dart';

// Typedef to help cleanup types related to this factory
typedef CryptoProviderFactory = FutureOr<CryptoProvider> Function(
    CryptoContext context);

/// Per Client instance object, which keeps track of registered
/// [CryptoProvider]s, with basic registry methods.
class CryptoRegistry {
  final Map<String, CryptoProvider> _providers = <String, CryptoProvider>{};

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

  /// Lookup if providerId is registered with this client
  /// otherwise, throw [CryptoProviderNotRegistered]
  CryptoProvider lookup(String id, {String? operation}) {
    final provider = _providers[id];
    if (provider == null) {
      throw CryptoProviderNotRegistered(
        _providerNotRegisteredMessage(id, operation: operation),
      );
    }
    return provider;
  }

  bool contains(String id) {
    return _providers.containsKey(id);
  }

  List<String> get registeredProviderIds {
    return _providers.keys.toList(growable: false);
  }

  String _providerNotRegisteredMessage(String id, {String? operation}) {
    final registeredIds = registeredProviderIds;
    final operationMessage = operation == null ? '' : ' Operation: $operation.';
    final registeredMessage =
        registeredIds.isEmpty ? 'none' : registeredIds.join(', ');
    return 'Crypto provider "$id" is not registered.'
        '$operationMessage Registered providers: $registeredMessage. '
        'Add it to AtClientPreference.crypto.providers or configure '
        'CryptoPolicy.onProviderNotFound.';
  }
}

/// Config which defines:
/// 1. CryptoProviders
/// 2. CryptoPolicy
/// 3. DefaultProviderId (what scheme?) ie: 'legacy'
class CryptoConfig {
  final String defaultProviderId;
  final List<CryptoProviderFactory> providers;
  final CryptoPolicy policy;

  const CryptoConfig({
    required this.defaultProviderId,
    this.providers = const [],
    this.policy = const CryptoPolicy(),
  });

  CryptoConfig.singleProvider({
    required this.defaultProviderId,
    required CryptoProviderFactory provider,
    this.policy = const CryptoPolicy(),
  }) : providers = [provider];

  const CryptoConfig.legacy()
      : defaultProviderId = 'legacy',
        providers = const [],
        policy = const CryptoPolicy();
}

/// Context which is injected into the provider factories for creation.
/// Opens up extensibility for specific types of Contexts.
class CryptoContext {
  final AtClient atClient;
  final Atsign currentAtSign;
  final AtChops? atChops;
  final CryptoStorage storage;

  const CryptoContext({
    required this.atClient,
    required this.currentAtSign,
    required this.atChops,
    required this.storage,
  });
}

/// Defines hooks which allow the user to have a reaction during specific
/// events / failure points.
///
/// ie: defining a policy for cryptography
class CryptoPolicy {
  const CryptoPolicy();

  FutureOr<CryptoFailureResolution> onProviderNotFound(
    CryptoProviderNotFoundContext context,
  ) {
    return const CryptoFailureResolution.throwError();
  }

  /// Called when a provider's [CryptoProvider.decrypt] throws. The default
  /// rethrows. A provider whose key material may still be in flight — e.g.
  /// the `group` provider when a peer hasn't yet shared the epoch key a
  /// ciphertext names — lets the app return [CryptoFailureResolution.retry]
  /// to re-attempt decryption once (typically after triggering a sync);
  /// any other resolution surfaces the failure unchanged.
  FutureOr<CryptoFailureResolution> onDecryptFailed(
    CryptoDecryptFailedContext context,
  ) {
    return const CryptoFailureResolution.throwError();
  }
}

abstract class CryptoFailureResolution {
  const CryptoFailureResolution();

  const factory CryptoFailureResolution.throwError() = ThrowCryptoError;

  const factory CryptoFailureResolution.retry() = RetryCryptoOperation;
}

class ThrowCryptoError extends CryptoFailureResolution {
  const ThrowCryptoError();
}

class RetryCryptoOperation extends CryptoFailureResolution {
  const RetryCryptoOperation();
}

class CryptoProviderNotFoundContext {
  final CryptoContext cryptoContext;
  final AtKey atKey;
  final String providerId;
  final AtException error;

  const CryptoProviderNotFoundContext({
    required this.cryptoContext,
    required this.atKey,
    required this.providerId,
    required this.error,
  });

  Future<void> registerProvider(CryptoProvider provider) async {
    await provider.initialize(cryptoContext);
    cryptoContext.atClient.cryptoRegistry.register(provider);
  }
}

/// Passed to [CryptoPolicy.onDecryptFailed] when a provider's decrypt throws.
/// [error] is whatever the provider raised (commonly a
/// `CryptoKeyUnavailableException` from the `group` provider when an epoch
/// key has not yet arrived) — not necessarily an [AtException].
class CryptoDecryptFailedContext {
  final CryptoContext cryptoContext;
  final AtKey atKey;
  final String providerId;
  final Object error;

  const CryptoDecryptFailedContext({
    required this.cryptoContext,
    required this.atKey,
    required this.providerId,
    required this.error,
  });
}

/// Abstract for persistent crypto keys that live in the at_servers
abstract interface class CryptoStorage {
  Future<String?> read(CryptoStorageKey key);

  Future<void> write(CryptoStorageKey key, String value);
}

class CryptoStorageKey {
  final Atsign owner;
  final Atsign recipient;
  final String namespace;
  final String name;

  const CryptoStorageKey({
    required this.owner,
    required this.recipient,
    required this.namespace,
    required this.name,
  });
}

/// Main implementation and contact point for pluggable encryption
/// this is the contract which all CryptoProvider implementations must follow.
abstract class CryptoProvider {
  String get id;

  Future<void> initialize(CryptoContext context) async {}

  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request);

  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request);
}

// Request & Response models used during runtime routing
// main consumers: [CryptoRuntime] and [CryptoProvider]

class CryptoEncryptRequest {
  final AtKey atKey;
  final dynamic plaintext;
  final AppMetadata? existingMetadata;

  const CryptoEncryptRequest({
    required this.atKey,
    required this.plaintext,
    this.existingMetadata,
  });
}

class CryptoEncryptResult {
  final dynamic ciphertext;
  final AppMetadata metadata;
  final bool isEncrypted;

  const CryptoEncryptResult({
    required this.ciphertext,
    required this.metadata,
    this.isEncrypted = true,
  });
}

class CryptoDecryptRequest {
  final AtKey atKey;
  final dynamic ciphertext;
  final AppMetadata metadata;

  const CryptoDecryptRequest({
    required this.atKey,
    required this.ciphertext,
    required this.metadata,
  });
}

class CryptoDecryptResult {
  final dynamic plaintext;

  const CryptoDecryptResult({required this.plaintext});
}
