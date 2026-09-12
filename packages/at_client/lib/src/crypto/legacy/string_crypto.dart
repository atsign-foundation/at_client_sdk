import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
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

/// Unwraps with the atSign's own RSA private key, which is the only half RSA
/// decryption reads.
///
/// `LocalSecondary` resolves that key across every tier the client has — an
/// injected `AtChops`, then its key source, then the keystore — so this works
/// for a client built either way. The public half is deliberately not
/// fetched: asking for material the operation does not use would refuse a
/// client that holds a private key and no public one, which is a shape the
/// keystore produces.
Future<RsaEncryptionAlgo> atSignDecryptionAlgo(AtClient atClient) async {
  final privateKey =
      await atClient.getLocalSecondary()!.getEncryptionPrivateKey();
  if (privateKey == null) {
    throw AtPrivateKeyNotFoundException(
        'no encryption private key for ${atClient.getCurrentAtSign()}, so a '
        'legacy shared key cannot be unwrapped',
        intent: Intent.fetchEncryptionPrivateKey,
        exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
  }
  return RsaEncryptionAlgo()
    ..atPrivateKey = AtPrivateKey.fromString(privateKey);
}

/// Wraps to the atSign's own RSA public key, so that only this atSign can
/// unwrap it again.
///
/// Resolved the same way as [atSignDecryptionAlgo], and needs the public half
/// because that is what encryption uses.
Future<RsaEncryptionAlgo> atSignEncryptionAlgo(AtClient atClient) async {
  final atSign = atClient.getCurrentAtSign()!;
  final publicKey =
      await atClient.getLocalSecondary()!.getEncryptionPublicKey(atSign);
  if (publicKey == null) {
    throw AtPublicKeyNotFoundException(
        'no encryption public key for $atSign, so a legacy shared key cannot '
        'be wrapped for it',
        intent: Intent.fetchEncryptionPublicKey,
        exceptionScenario: ExceptionScenario.fetchEncryptionKeys);
  }
  return RsaEncryptionAlgo()..atPublicKey = AtPublicKey.fromString(publicKey);
}
