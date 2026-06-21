import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_commons/at_commons.dart';

/// Routes encryption/decryption to the [CryptoProvider] named by an [AtKey]'s
/// `appMetadata.providerId`.
class CryptoRuntime {
  static const String legacyProviderId = 'legacy';

  final AtClient _atClient;

  CryptoRuntime(this._atClient);

  Future<String> encryptForPut(AtKey atKey, dynamic value) async {
    try {
      return await _provider(atKey, 'put')
          .encrypt(_context(), atKey, _requireString(value));
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

  Future<String> encryptForNotification(AtKey atKey, dynamic value) async {
    try {
      return await _provider(atKey, 'notify')
          .encrypt(_context(), atKey, _requireString(value));
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

  Future<dynamic> decryptForGet(AtKey atKey, dynamic value) =>
      _decrypt(atKey, value, 'get');

  Future<dynamic> decryptForSyncConflict(AtKey atKey, dynamic value) =>
      _decrypt(atKey, value, 'sync conflict');

  Future<dynamic> decryptForNotification(AtKey atKey, dynamic value) async {
    try {
      return await _decrypt(atKey, value, 'notify');
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

  Future<dynamic> _decrypt(AtKey atKey, dynamic value, String operation) {
    // A null ciphertext (e.g. a notification with no value) is passed to the
    // provider as '' so it surfaces the provider's own "encrypted value is
    // null" error rather than a raw cast TypeError.
    return _provider(atKey, operation)
        .decrypt(_context(), atKey, (value as String?) ?? '');
  }

  CryptoProvider _provider(AtKey atKey, String operation) {
    final providerId =
        atKey.metadata.appMetadata?.providerId ?? legacyProviderId;
    return _atClient.cryptoRegistry.lookup(providerId, lookupReason: operation);
  }

  CryptoContext _context() => CryptoContext(atClient: _atClient);

  // The provider contract is String-typed; reject a non-String plaintext at
  // the boundary with the same error the value pipeline gave before, rather
  // than silently stringifying it.
  String _requireString(dynamic value) {
    if (value is! String) {
      throw AtEncryptionException(
        'Invalid value type found: ${value.runtimeType}. '
        'Valid value type is String',
      );
    }
    return value;
  }
}
