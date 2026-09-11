import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Encrypts [value] with [algorithm] and returns the ciphertext in base64.
///
/// A symmetric [algorithm] requires [iv]. A failure inside the algorithm is
/// reported as [AtEncryptionException] carrying the algorithm's own message,
/// which is the type the legacy encryption paths handle; a malformed [value]
/// surfaces as whatever the conversion throws, outside that mapping.
Future<String> encryptStringToBase64(
    String value, AtEncryptionAlgorithm<Uint8List, Uint8List> algorithm,
    {InitialisationVector? iv}) async {
  final plainBytes = Uint8List.fromList(utf8.encode(value));
  final Uint8List cipherBytes;
  try {
    cipherBytes =
        algorithm is SymmetricEncryptionAlgorithm<Uint8List, Uint8List>
            ? await algorithm.encrypt(plainBytes, iv: iv!)
            : await algorithm.encrypt(plainBytes);
  } on Exception catch (e) {
    throw AtEncryptionException(e.toString())
      ..stack(AtChainedException(Intent.shareData,
          ExceptionScenario.encryptionFailed, 'Failed to encrypt $e'));
  }
  return base64.encode(cipherBytes);
}

/// Decrypts base64 [value] with [algorithm] and returns the plaintext.
///
/// A symmetric [algorithm] is refused without an [iv] rather than failing
/// inside the cipher. A failure inside the algorithm is reported as
/// [AtDecryptionException] carrying the algorithm's own message; a [value]
/// that is not base64, or plaintext that is not UTF-8, surfaces as whatever
/// the conversion throws, outside that mapping.
Future<String> decryptStringFromBase64(
    String value, AtEncryptionAlgorithm<Uint8List, Uint8List> algorithm,
    {InitialisationVector? iv}) async {
  if (algorithm is SymmetricEncryptionAlgorithm && iv == null) {
    throw AtDecryptionException(
        'Initialization vector required for decryption using SymmetricKey');
  }
  final cipherBytes = base64Decode(value);
  final Uint8List plainBytes;
  try {
    plainBytes = algorithm is SymmetricEncryptionAlgorithm<Uint8List, Uint8List>
        ? await algorithm.decrypt(cipherBytes, iv: iv!)
        : await algorithm.decrypt(cipherBytes);
  } on Exception catch (e) {
    throw AtDecryptionException(e.toString())
      ..stack(AtChainedException(Intent.decryptData,
          ExceptionScenario.decryptionFailed, 'Failed to decrypt $e'));
  }
  return utf8.decode(plainBytes);
}
