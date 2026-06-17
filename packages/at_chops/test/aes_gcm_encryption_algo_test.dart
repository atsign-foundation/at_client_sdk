import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('AES-256-GCM round trip', () {
    final aesKey = AESKey.generate(32);
    final algo = AesGcm256EncryptionAlgo(aesKey);

    test('encrypt then decrypt returns the plaintext', () async {
      final iv = AtChopsUtil.generateRandomIV(12);
      final plain = Uint8List.fromList(utf8.encode('hello, alice'));

      final encrypted = await algo.encrypt(plain, iv: iv);
      expect(
          encrypted.length, plain.length + AesGcm256EncryptionAlgo.tagLength);

      final decrypted = await algo.decrypt(encrypted, iv: iv);
      expect(utf8.decode(decrypted), 'hello, alice');
    });

    test('tampered ciphertext, tag or nonce throws AtDecryptionException',
        () async {
      final iv = AtChopsUtil.generateRandomIV(12);
      final plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final encrypted = await algo.encrypt(plain, iv: iv);

      final tamperedCt = Uint8List.fromList(encrypted);
      tamperedCt[0] ^= 0x01;
      expect(() => algo.decrypt(tamperedCt, iv: iv),
          throwsA(isA<AtDecryptionException>()));

      final tamperedTag = Uint8List.fromList(encrypted);
      tamperedTag[encrypted.length - 1] ^= 0x01;
      expect(() => algo.decrypt(tamperedTag, iv: iv),
          throwsA(isA<AtDecryptionException>()));

      final otherIv = AtChopsUtil.generateRandomIV(12);
      expect(() => algo.decrypt(encrypted, iv: otherIv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('a nonce of the wrong length is rejected', () async {
      final plain = Uint8List.fromList([1, 2, 3]);
      expect(() => algo.encrypt(plain), throwsA(isA<AtEncryptionException>()));
      expect(() => algo.encrypt(plain, iv: AtChopsUtil.generateRandomIV(16)),
          throwsA(isA<AtEncryptionException>()));
    });

    test('a key that is not 256 bits is rejected', () async {
      final algo128 = AesGcm256EncryptionAlgo(AESKey.generate(16));
      expect(
          () => algo128.encrypt(Uint8List.fromList([1]),
              iv: AtChopsUtil.generateRandomIV(12)),
          throwsA(isA<AtEncryptionException>()));
    });
  });

  group('NIST GCM vectors (McGrew & Viega, 256-bit, no AAD)', () {
    // Test case 13: empty plaintext
    test('case 13: zero key/nonce, empty plaintext', () async {
      final algo = AesGcm256EncryptionAlgo(AESKey(base64Encode(Uint8List(32))));
      final iv = InitialisationVector(Uint8List(12));
      final out = await algo.encrypt(Uint8List(0), iv: iv);
      // output is tag only
      expect(out, _hex('530f8afbc74536b9a963b4f1c4cb738b'));
    });

    // Test case 14: 16 zero bytes of plaintext
    test('case 14: zero key/nonce, 16-byte zero plaintext', () async {
      final algo = AesGcm256EncryptionAlgo(AESKey(base64Encode(Uint8List(32))));
      final iv = InitialisationVector(Uint8List(12));
      final out = await algo.encrypt(Uint8List(16), iv: iv);
      expect(
          out,
          _hex('cea7403d4d606b6e074ec5d3baf39d18'
              'd0d1c8a799996bf0265b98b5d48ab919'));
      // and decrypts back
      final plain = await algo.decrypt(out, iv: iv);
      expect(plain, Uint8List(16));
    });
  });
}
