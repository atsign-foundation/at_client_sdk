import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/legacy/legacy_decryption.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:at_commons/at_commons.dart';

/// The pre-pluggable encryption scheme, wrapped as a [CryptoProvider].
class LegacyCryptoProvider extends CryptoProvider {
  static const String providerId = 'legacy';

  @override
  String get id => providerId;

  @override
  Future<String> encrypt(
    CryptoContext context,
    AtKey atKey,
    String value,
  ) async {
    final legacy = LegacyEncryption.build(atKey, context.atClient);
    final ciphertext = await legacy.encrypt(atKey, value);
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return ciphertext as String;
  }

  @override
  Future<String> decrypt(
    CryptoContext context,
    AtKey atKey,
    String value,
  ) async {
    final legacy = LegacyDecryption.build(atKey, context.atClient);
    final plaintext = await legacy.decrypt(atKey, value);
    return plaintext as String;
  }
}
