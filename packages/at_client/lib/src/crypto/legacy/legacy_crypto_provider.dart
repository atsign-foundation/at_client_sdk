import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/legacy/legacy_decryption.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:at_commons/at_commons.dart';

class LegacyCryptoProvider extends CryptoProvider {
  static const String providerId = 'legacy';

  final AtClient _atClient;

  LegacyCryptoProvider(this._atClient);

  @override
  String get id => providerId;

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    final legacy = LegacyEncryption.build(request.atKey, _atClient);
    final ciphertext = await legacy.encrypt(request.atKey, request.plaintext);
    return CryptoEncryptResult(
      ciphertext: ciphertext,
      metadata: AppMetadata(providerId: id),
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    final legacy = LegacyDecryption.build(request.atKey, _atClient);
    final plaintext = await legacy.decrypt(request.atKey, request.ciphertext);
    return CryptoDecryptResult(plaintext: plaintext);
  }
}
