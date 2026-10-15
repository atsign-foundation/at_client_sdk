import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// An AES-GCM nonce and its ciphertext with the 16-byte tag appended.
typedef Sealed = ({Uint8List iv, Uint8List ct});

final _gcm = AesGcm.with256bits();
const _macLength = 16;

/// [length] bytes from a cryptographically secure source.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// [plaintext] sealed under the 32-byte [key] with [iv], or a random 96-bit
/// IV when [iv] is null.
Future<Sealed> gcmSeal(List<int> key, List<int> plaintext, List<int> aad,
    {Uint8List? iv}) async {
  final box = await _gcm.encrypt(plaintext,
      secretKey: SecretKey(key), nonce: iv ?? randomBytes(12), aad: aad);
  return (
    iv: Uint8List.fromList(box.nonce),
    ct: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
  );
}

/// The plaintext, or null when [sealed] fails authentication under [key].
Future<Uint8List?> gcmOpen(List<int> key, Sealed sealed, List<int> aad) async {
  if (sealed.ct.length < _macLength) return null;
  final split = sealed.ct.length - _macLength;
  try {
    return Uint8List.fromList(await _gcm.decrypt(
        SecretBox(sealed.ct.sublist(0, split),
            nonce: sealed.iv, mac: Mac(sealed.ct.sublist(split))),
        secretKey: SecretKey(key),
        aad: aad));
  } on SecretBoxAuthenticationError {
    return null;
  } on ArgumentError {
    return null;
  }
}
