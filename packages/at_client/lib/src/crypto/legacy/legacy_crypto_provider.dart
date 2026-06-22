import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/legacy/legacy_decryption.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:at_commons/at_commons.dart';

/// The pre-pluggable encryption scheme, wrapped as a [CryptoProvider].
class LegacyCryptoProvider extends CryptoProvider {
  static const String providerId = legacyCryptoProviderId;

  @override
  String get id => providerId;

  @override
  Future<String> encrypt(
    CryptoContext context,
    AtKey atKey,
    String plaintext,
  ) async {
    final legacy = LegacyEncryption.build(atKey, context.atClient);
    // The runtime stamps appMetadata.providerId + isEncrypted on return.
    final ciphertext = await legacy.encrypt(atKey, plaintext);
    return ciphertext as String;
  }

  @override
  Future<String> decrypt(
    CryptoContext context,
    AtKey atKey,
    String ciphertext,
  ) async {
    final legacy = LegacyDecryption.build(atKey, context.atClient);
    final plaintext = await legacy.decrypt(atKey, ciphertext);
    return plaintext as String;
  }
}
