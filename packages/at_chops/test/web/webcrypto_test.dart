@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops_web.dart';
import 'package:test/test.dart';

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('WebCryptoAesCtr', () {
    test('matches the VM across the low-64-bit counter carry', () async {
      final key =
          AESKey(base64Encode(Uint8List.fromList(List.generate(32, (i) => i))));
      final iv = InitialisationVector(Uint8List.fromList([
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, //
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      ]));
      final plain = bytesOf('low64 carry boundary');
      final algo = WebCryptoAesCtr(key);

      final encrypted = await algo.encrypt(plain, iv: iv);
      expect(hexOf(encrypted),
          '076fa7bcf8050ca8d06c0584d76a030c519db4dc61384e8bfae479c20bf02d80');
      expect(await algo.decrypt(encrypted, iv: iv), plain);
    });

    for (final keyBytes in [16, 32]) {
      final key = AESKey.generate(keyBytes);
      final iv =
          InitialisationVector(Uint8List.fromList(List.generate(16, (i) => i)));
      for (final length in [0, 1, 15, 16, 17, 31, 32, 33, 1000]) {
        test(
            'AES-${keyBytes * 8}, $length bytes: cross-decrypts with '
            'AESEncryptionAlgo', () async {
          final plain =
              Uint8List.fromList(List.generate(length, (i) => i & 0xff));
          final web = WebCryptoAesCtr(key);
          final dart = AESEncryptionAlgo(key);

          final webEncrypted = await web.encrypt(plain, iv: iv);
          expect(webEncrypted, hasLength(length + 16 - length % 16));
          expect(await dart.decrypt(webEncrypted, iv: iv), plain);
          expect(await web.decrypt(await dart.encrypt(plain, iv: iv), iv: iv),
              plain);
        });
      }
    }
  });

  group('WebCryptoPbkdf2Sha256Kdf', () {
    test('matches the PBKDF2-HMAC-SHA256 vector', () async {
      final derived = await const WebCryptoPbkdf2Sha256Kdf().derive(
          bytesOf('password'),
          bytesOf('salt'),
          const Pbkdf2Sha256Params(iterations: 4096));
      expect(hexOf(derived),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('matches Pbkdf2Sha256Kdf', () async {
      const params = Pbkdf2Sha256Params(iterations: 1000);
      final secret = bytesOf('mysecretpassword');
      final salt = bytesOf('somesalt');
      expect(
          await const WebCryptoPbkdf2Sha256Kdf().derive(secret, salt, params),
          await const Pbkdf2Sha256Kdf().derive(secret, salt, params));
    });

    test('rejects Argon2idParams', () {
      expect(
          () => const WebCryptoPbkdf2Sha256Kdf().derive(
              Uint8List(16),
              Uint8List(16),
              const Argon2idParams(
                  memoryKiB: 128, iterations: 1, parallelism: 1)),
          throwsArgumentError);
    });
  });
}
