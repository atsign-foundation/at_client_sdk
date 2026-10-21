import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for RSA encryption/decryption', () {
    // Key material is the raw DER bytes returned by
    // RsaSigningAlgo.generateKeyPair(), which is exactly what
    // RsaEncryptionAlgo consumes.
    for (final keySize in [2048, 4096]) {
      test('Test asymmetric encryption/decryption using rsa $keySize',
          () async {
        final algo = RsaEncryptionAlgo();
        final (:publicKey, :secretKey) =
            await RsaSigningAlgo(keySize: keySize).generateKeyPair();
        final dataToEncrypt = 'Hello World12!@';

        final encryptedData =
            algo.encrypt(utf8.encode(dataToEncrypt), publicKey);
        final decryptedData = algo.decrypt(encryptedData, secretKey);

        expect(utf8.decode(decryptedData), dataToEncrypt);
      });
    }

    test('an empty plaintext encrypts to one modulus-wide block', () async {
      final algo = RsaEncryptionAlgo();
      final (:publicKey, :secretKey) =
          await RsaSigningAlgo(keySize: 2048).generateKeyPair();

      final encrypted = algo.encrypt(Uint8List(0), publicKey);

      expect(encrypted, hasLength(256));
      expect(algo.decrypt(encrypted, secretKey), isEmpty);
    });
  });
}
