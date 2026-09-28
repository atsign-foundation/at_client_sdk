import 'dart:convert';

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
  });
}
