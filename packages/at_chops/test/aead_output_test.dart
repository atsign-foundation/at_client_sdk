import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/encryption/aead_output.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart'
    show aesGcmUpdate;
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'no_concat_cipher.dart';

/// Catalogue: features/at_chops/aes_gcm_output.feature
void main() {
  for (final (String name, Cipher cipher) in [
    ('AES-256-GCM', AesGcm.with256bits()),
    ('ChaCha20-Poly1305', Chacha20.poly1305Aead()),
  ]) {
    test(
        'The pure-Dart encrypt step copies the ciphertext and tag into one buffer of exactly their length ($name)',
        () async {
      final Uint8List key =
          Uint8List.fromList(List<int>.generate(32, (int i) => i));
      final Uint8List nonce =
          Uint8List.fromList(List<int>.generate(12, (int i) => 0xa0 + i));
      final Uint8List plain =
          Uint8List.fromList(List<int>.generate(1000, (int i) => i & 0xff));
      final Uint8List aad =
          Uint8List.fromList(List<int>.generate(7, (int i) => 0x50 + i));

      final SecretBox box = await cipher.encrypt(plain,
          secretKey: SecretKey(key), nonce: nonce, aad: aad);
      final Uint8List out = await aeadEncrypt(NoConcatCipher(cipher), plain,
          key: key, nonce: nonce, aad: aad);

      expectExactLengthOutput(out, [...box.cipherText, ...box.mac.bytes]);
    });
  }

  // Both directions: a shorter length misplaces the tag, and a longer one
  // writes or reads past the end of a native buffer.
  for (final (String operation, String input, String output, int reported) in [
    ('EVP_EncryptUpdate', 'plaintext', 'ciphertext', 59),
    ('EVP_EncryptUpdate', 'plaintext', 'ciphertext', 61),
    ('EVP_DecryptUpdate', 'ciphertext', 'plaintext', 59),
    ('EVP_DecryptUpdate', 'ciphertext', 'plaintext', 61),
  ]) {
    test(
        'The AES-256-GCM FFI update step refuses a reported length that differs from its input length ($operation, $reported)',
        () {
      expect(
          () => aesGcmUpdate((Pointer<Int32> outLen) {
                outLen.value = reported;
                return 1;
              }, 60,
                  operation: operation, inputName: input, outputName: output),
          throwsA(isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              '$operation produced a $reported-byte $output, expected 60')),
          reason: 'the update step accepted a reported $reported-byte $output '
              'for a 60-byte $input');
    });
  }
}
