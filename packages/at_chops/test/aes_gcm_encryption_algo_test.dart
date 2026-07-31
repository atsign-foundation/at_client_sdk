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

const int tagLength = AesGcm256EncryptionAlgo.tagLength;

void main() {
  group('AES-256-GCM round trip', () {
    final algo = AesGcm256EncryptionAlgo();
    final key = algo.generateKey();

    test('encrypt then decrypt returns the plaintext', () async {
      final iv = InitialisationVector.random(12);
      final plain = Uint8List.fromList(utf8.encode('hello, alice'));

      final encrypted = await algo.encrypt(plain, key, iv: iv);
      expect(
          encrypted.length, plain.length + AesGcm256EncryptionAlgo.tagLength);

      final decrypted = await algo.decrypt(encrypted, key, iv: iv);
      expect(utf8.decode(decrypted), 'hello, alice');
    });

    test('tampered ciphertext, tag or nonce throws AtDecryptionException',
        () async {
      final iv = InitialisationVector.random(12);
      final plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final encrypted = await algo.encrypt(plain, key, iv: iv);

      final tamperedCt = Uint8List.fromList(encrypted);
      tamperedCt[0] ^= 0x01;
      expect(() => algo.decrypt(tamperedCt, key, iv: iv),
          throwsA(isA<AtDecryptionException>()));

      final tamperedTag = Uint8List.fromList(encrypted);
      tamperedTag[encrypted.length - 1] ^= 0x01;
      expect(() => algo.decrypt(tamperedTag, key, iv: iv),
          throwsA(isA<AtDecryptionException>()));

      final otherIv = InitialisationVector.random(12);
      expect(() => algo.decrypt(encrypted, key, iv: otherIv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('a nonce of the wrong length is rejected', () async {
      final plain = Uint8List.fromList([1, 2, 3]);
      expect(
          () => algo.encrypt(plain, key, iv: InitialisationVector.random(16)),
          throwsA(isA<AtEncryptionException>()));
    });

    test('a key that is not 256 bits is rejected', () async {
      final key128 = AesCtrEncryptionAlgo(16).generateKey();
      expect(
          () => algo.encrypt(Uint8List.fromList([1]), key128,
              iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));
      expect(
          () => algo.decrypt(Uint8List(tagLength + 1), key128,
              iv: InitialisationVector.random(12)),
          throwsA(isA<AtDecryptionException>()));
    });
  });

  group('AES-256-GCM with AAD', () {
    final algo = AesGcm256EncryptionAlgo();
    final key = algo.generateKey();

    test('round-trips when AAD matches', () async {
      final iv = InitialisationVector.random(12);
      final plain = Uint8List.fromList(utf8.encode('secret body'));
      final aad = utf8.encode('authenticated header');

      final encrypted = await algo.encrypt(plain, key, iv: iv, aad: aad);
      final decrypted = await algo.decrypt(encrypted, key, iv: iv, aad: aad);
      expect(utf8.decode(decrypted), 'secret body');
    });

    test('mismatched AAD throws AtDecryptionException', () async {
      final iv = InitialisationVector.random(12);
      final plain = Uint8List.fromList(utf8.encode('secret body'));

      final encrypted =
          await algo.encrypt(plain, key, iv: iv, aad: utf8.encode('header-A'));
      expect(
          () => algo.decrypt(encrypted, key,
              iv: iv, aad: utf8.encode('header-B')),
          throwsA(isA<AtDecryptionException>()));
    });

    test('AAD present at encrypt but absent at decrypt throws', () async {
      final iv = InitialisationVector.random(12);
      final plain = Uint8List.fromList(utf8.encode('secret body'));

      final encrypted =
          await algo.encrypt(plain, key, iv: iv, aad: utf8.encode('header'));
      // default decrypt (empty AAD) must not authenticate.
      expect(() => algo.decrypt(encrypted, key, iv: iv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('empty AAD equals omitting it (backward compatible)', () async {
      final iv = InitialisationVector.random(12);
      final plain = Uint8List.fromList(utf8.encode('xyz'));

      final withEmptyAad =
          await algo.encrypt(plain, key, iv: iv, aad: const []);
      final withoutAad = await algo.encrypt(plain, key, iv: iv);
      expect(withEmptyAad, equals(withoutAad));
    });
  });

  group('NIST GCM vectors (McGrew & Viega, 256-bit, no AAD)', () {
    // Test case 13: empty plaintext
    test('case 13: zero key/nonce, empty plaintext', () async {
      final algo = AesGcm256EncryptionAlgo();
      final iv = InitialisationVector(Uint8List(12));
      final out = await algo.encrypt(Uint8List(0), Uint8List(32), iv: iv);
      // output is tag only
      expect(out, _hex('530f8afbc74536b9a963b4f1c4cb738b'));
    });

    // Test case 14: 16 zero bytes of plaintext
    test('case 14: zero key/nonce, 16-byte zero plaintext', () async {
      final algo = AesGcm256EncryptionAlgo();
      final iv = InitialisationVector(Uint8List(12));
      final out = await algo.encrypt(Uint8List(16), Uint8List(32), iv: iv);
      expect(
          out,
          _hex('cea7403d4d606b6e074ec5d3baf39d18'
              'd0d1c8a799996bf0265b98b5d48ab919'));
      // and decrypts back
      final plain = await algo.decrypt(out, Uint8List(32), iv: iv);
      expect(plain, Uint8List(16));
    });
  });
}
