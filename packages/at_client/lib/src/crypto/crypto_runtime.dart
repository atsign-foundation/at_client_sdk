import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/crypto_storage.dart';
import 'package:at_commons/at_commons.dart';

/// Centralizes crypto provider routing without changing the metadata wire
/// shape.
class CryptoRuntime {
  static const String legacyProviderId = 'legacy';

  final AtClient _atClient;

  CryptoRuntime(this._atClient);

  Future<CryptoEncryptResult> encryptForPut(AtKey atKey, dynamic value) async {
    final provider = await _lookupProvider(
      atKey,
      operation: 'put',
      onFailure: (e) => e.stack(
        AtChainedException(
          Intent.fetchCryptoProvider,
          ExceptionScenario.decryptionFailed,
          'Failed to fetch crypto provider',
        ),
      ),
    );
    try {
      final result = await provider.encrypt(
        CryptoEncryptRequest(
          atKey: atKey,
          plaintext: value,
          existingMetadata: _metadataFor(atKey, provider),
        ),
      );
      atKey.metadata.appMetadata = result.metadata;
      atKey.metadata.isEncrypted = result.isEncrypted;
      return result;
    } on AtException catch (e) {
      e.stack(
        AtChainedException(
          Intent.shareData,
          ExceptionScenario.encryptionFailed,
          'Failed to encrypt the data',
        ),
      );
      rethrow;
    }
  }

  Future<dynamic> decryptForGet(AtKey atKey, dynamic value) async {
    return _decrypt(atKey, value, operation: 'get');
  }

  Future<dynamic> encryptForNotification(AtKey atKey, dynamic value) async {
    final provider = await _lookupProvider(
      atKey,
      operation: 'notify',
      onFailure: (e) => e.stack(
        AtChainedException(
          Intent.fetchCryptoProvider,
          ExceptionScenario.decryptionFailed,
          'Failed to fetch crypto provider',
        ),
      ),
    );
    try {
      final result = await provider.encrypt(
        CryptoEncryptRequest(
          atKey: atKey,
          plaintext: value,
          existingMetadata: _metadataFor(atKey, provider),
        ),
      );
      atKey.metadata.appMetadata = result.metadata;
      atKey.metadata.isEncrypted = result.isEncrypted;
      return result.ciphertext;
    } on AtException catch (e) {
      e.stack(
        AtChainedException(
          Intent.notifyData,
          ExceptionScenario.encryptionFailed,
          e.message,
        ),
      );
      rethrow;
    }
  }

  Future<dynamic> decryptForNotification(AtKey atKey, dynamic value) async {
    final provider = await _lookupProvider(
      atKey,
      operation: 'notify',
      onFailure: (e) => e.stack(
        AtChainedException(
          Intent.fetchCryptoProvider,
          ExceptionScenario.decryptionFailed,
          'Failed to fetch crypto provider',
        ),
      ),
    );
    try {
      final result = await provider.decrypt(
        CryptoDecryptRequest(
          atKey: atKey,
          ciphertext: value,
          metadata: _metadataFor(atKey, provider),
        ),
      );
      return result.plaintext;
    } on AtException catch (e) {
      e.stack(
        AtChainedException(
          Intent.notifyData,
          ExceptionScenario.encryptionFailed,
          e.message,
        ),
      );
      rethrow;
    }
  }

  Future<dynamic> encryptForNotificationService(
    AtKey atKey,
    dynamic value, {
    required String providerId,
  }) async {
    final provider = await _lookupProviderById(
      atKey,
      providerId,
      operation: 'notify',
    );
    final result = await provider.encrypt(
      CryptoEncryptRequest(
        atKey: atKey,
        plaintext: value,
        existingMetadata: _metadataFor(atKey, provider),
      ),
    );
    atKey.metadata.appMetadata = result.metadata;
    atKey.metadata.isEncrypted = result.isEncrypted;
    return result.ciphertext;
  }

  Future<dynamic> decryptForSyncConflict(AtKey atKey, dynamic value) async {
    return _decrypt(atKey, value, operation: 'sync conflict');
  }

  Future<dynamic> _decrypt(
    AtKey atKey,
    dynamic value, {
    required String operation,
  }) async {
    final provider = await _lookupProvider(atKey, operation: operation);
    final result = await provider.decrypt(
      CryptoDecryptRequest(
        atKey: atKey,
        ciphertext: value,
        metadata: _metadataFor(atKey, provider),
      ),
    );
    return result.plaintext;
  }

  Future<CryptoProvider> _lookupProvider(
    AtKey atKey, {
    String? operation,
    void Function(AtException e)? onFailure,
  }) {
    final providerId =
        atKey.metadata.appMetadata?.providerId ?? legacyProviderId;
    return _lookupProviderById(
      atKey,
      providerId,
      operation: operation,
      onFailure: onFailure,
    );
  }

  Future<CryptoProvider> _lookupProviderById(
    AtKey atKey,
    String providerId, {
    String? operation,
    void Function(AtException e)? onFailure,
  }) async {
    try {
      return _atClient.cryptoRegistry.lookup(providerId, operation: operation);
    } on CryptoProviderNotRegistered catch (e) {
      final provider = await _handleProviderNotFound(atKey, providerId, e);
      if (provider == null) {
        try {
          return _atClient.cryptoRegistry.lookup(
            providerId,
            operation: operation,
          );
        } on AtException catch (retryError) {
          onFailure?.call(retryError);
          rethrow;
        }
      }
      onFailure?.call(e);
      rethrow;
    } on AtException catch (e) {
      onFailure?.call(e);
      rethrow;
    }
  }

  AppMetadata _metadataFor(AtKey atKey, CryptoProvider provider) {
    final appMetadata = atKey.metadata.appMetadata;
    if (appMetadata == null) {
      return AppMetadata(provider.id);
    }
    return appMetadata;
  }

  Future<CryptoFailureResolution?> _handleProviderNotFound(
    AtKey atKey,
    String providerId,
    AtException error,
  ) async {
    final preferences = _atClient.getPreferences();
    final resolution = await preferences?.crypto.policy.onProviderNotFound(
      CryptoProviderNotFoundContext(
        cryptoContext: CryptoContext(
          atClient: _atClient,
          currentAtSign: (_atClient.getCurrentAtSign() ?? '').toAtsign(),
          atChops: _atClient.atChops,
          storage: CryptoSecondaryStorage(_atClient),
        ),
        atKey: atKey,
        providerId: providerId,
        error: error,
      ),
    );
    return resolution;
  }
}
