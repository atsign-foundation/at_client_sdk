import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

/// Encrypts [plaintext] with [cipher] and returns the ciphertext followed by
/// the tag in one [Uint8List] of exactly their combined length, copying each
/// once.
Future<Uint8List> aeadEncrypt(crypto.Cipher cipher, List<int> plaintext,
    {required List<int> key,
    required List<int> nonce,
    required List<int> aad}) async {
  final crypto.SecretBox box = await cipher.encrypt(plaintext,
      secretKey: crypto.SecretKey(key), nonce: nonce, aad: aad);
  final List<int> cipherText = box.cipherText;
  final List<int> tag = box.mac.bytes;
  return Uint8List(cipherText.length + tag.length)
    ..setRange(0, cipherText.length, cipherText)
    ..setRange(cipherText.length, cipherText.length + tag.length, tag);
}
