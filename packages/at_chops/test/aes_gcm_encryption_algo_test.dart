import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

const int _nonceLen = AesGcm256EncryptionAlgo.nonceLength;
const int _tagLen = AesGcm256EncryptionAlgo.tagLength;

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
      final plain = Uint8List.fromList(utf8.encode('hello, alice'));

      final encrypted = await algo.encrypt(plain);
      // nonce(12) || ciphertext || tag(16)
      expect(encrypted.length, _nonceLen + plain.length + _tagLen);

      final decrypted = await algo.decrypt(encrypted);
      expect(utf8.decode(decrypted), 'hello, alice');
    });

    test('every encryption draws a fresh nonce', () async {
      final plain = Uint8List.fromList(utf8.encode('same plaintext'));
      final seenNonces = <String>{};
      for (var i = 0; i < 64; i++) {
        final encrypted = await algo.encrypt(plain);
        final nonceHex = base64Encode(encrypted.sublist(0, _nonceLen));
        expect(seenNonces.add(nonceHex), isTrue,
            reason: 'nonce repeated after ${seenNonces.length} encryptions');
      }
    });

    test('supplying an IV is rejected — the algorithm owns the nonce',
        () async {
      final plain = Uint8List.fromList(utf8.encode('x'));
      expect(() => algo.encrypt(plain, iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));

      final encrypted = await algo.encrypt(plain);
      expect(
          () => algo.decrypt(encrypted, iv: InitialisationVector.random(12)),
          throwsA(isA<AtDecryptionException>()));
    });

    test('tampered nonce, ciphertext or tag throws AtDecryptionException',
        () async {
      final plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final encrypted = await algo.encrypt(plain);

      final tamperedNonce = Uint8List.fromList(encrypted);
      tamperedNonce[0] ^= 0x01;
      expect(() => algo.decrypt(tamperedNonce),
          throwsA(isA<AtDecryptionException>()));

      final tamperedCt = Uint8List.fromList(encrypted);
      tamperedCt[_nonceLen] ^= 0x01;
      expect(() => algo.decrypt(tamperedCt),
          throwsA(isA<AtDecryptionException>()));

      final tamperedTag = Uint8List.fromList(encrypted);
      tamperedTag[encrypted.length - 1] ^= 0x01;
      expect(() => algo.decrypt(tamperedTag),
          throwsA(isA<AtDecryptionException>()));
    });

    test('input shorter than nonce + tag is rejected', () async {
      expect(() => algo.decrypt(Uint8List(_nonceLen + _tagLen - 1)),
          throwsA(isA<AtDecryptionException>()));
    });

    test('a key that is not 256 bits is rejected', () async {
      final algo128 = AesGcm256EncryptionAlgo(AESKey.generate(16));
      expect(() => algo128.encrypt(Uint8List.fromList([1])),
          throwsA(isA<AtEncryptionException>()));
    });
  });

  group('AES-256-GCM with AAD', () {
    final algo = AesGcm256EncryptionAlgo(AESKey.generate(32));

    test('round-trips when AAD matches', () async {
      final plain = Uint8List.fromList(utf8.encode('secret body'));
      final aad = utf8.encode('authenticated header');

      final encrypted = await algo.encrypt(plain, aad: aad);
      final decrypted = await algo.decrypt(encrypted, aad: aad);
      expect(utf8.decode(decrypted), 'secret body');
    });

    test('mismatched AAD throws AtDecryptionException', () async {
      final plain = Uint8List.fromList(utf8.encode('secret body'));

      final encrypted = await algo.encrypt(plain, aad: utf8.encode('header-A'));
      expect(() => algo.decrypt(encrypted, aad: utf8.encode('header-B')),
          throwsA(isA<AtDecryptionException>()));
    });

    test('AAD present at encrypt but absent at decrypt throws', () async {
      final plain = Uint8List.fromList(utf8.encode('secret body'));

      final encrypted = await algo.encrypt(plain, aad: utf8.encode('header'));
      // default decrypt (empty AAD) must not authenticate.
      expect(() => algo.decrypt(encrypted),
          throwsA(isA<AtDecryptionException>()));
    });

    test('empty AAD equals omitting it (backward compatible)', () async {
      // Explicit-nonce API so the two outputs are byte-comparable — the
      // public API prepends a different random nonce each call.
      final plain = Uint8List.fromList(utf8.encode('xyz'));
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));

      final withEmptyAad =
          await algo.encryptWithNonce(plain, nonce: nonce, aad: const []);
      final withoutAad = await algo.encryptWithNonce(plain, nonce: nonce);
      expect(withEmptyAad, equals(withoutAad));
    });
  });

  group('explicit-nonce API (single-use keys and KAT vectors only)', () {
    test('a nonce of the wrong length is rejected', () async {
      final algo = AesGcm256EncryptionAlgo(AESKey.generate(32));
      final plain = Uint8List.fromList([1, 2, 3]);
      expect(() => algo.encryptWithNonce(plain, nonce: Uint8List(16)),
          throwsA(isA<AtEncryptionException>()));
      expect(
          () => algo.decryptWithNonce(Uint8List(_tagLen + 1),
              nonce: Uint8List(16)),
          throwsA(isA<AtDecryptionException>()));
    });

    group('NIST GCM vectors (McGrew & Viega, 256-bit, no AAD)', () {
      // Test case 13: empty plaintext
      test('case 13: zero key/nonce, empty plaintext', () async {
        final algo =
            AesGcm256EncryptionAlgo(AESKey(base64Encode(Uint8List(32))));
        final out =
            await algo.encryptWithNonce(Uint8List(0), nonce: Uint8List(12));
        // output is tag only
        expect(out, _hex('530f8afbc74536b9a963b4f1c4cb738b'));
      });

      // Test case 14: 16 zero bytes of plaintext
      test('case 14: zero key/nonce, 16-byte zero plaintext', () async {
        final algo =
            AesGcm256EncryptionAlgo(AESKey(base64Encode(Uint8List(32))));
        final out =
            await algo.encryptWithNonce(Uint8List(16), nonce: Uint8List(12));
        expect(
            out,
            _hex('cea7403d4d606b6e074ec5d3baf39d18'
                'd0d1c8a799996bf0265b98b5d48ab919'));
        // and decrypts back
        final plain = await algo.decryptWithNonce(out, nonce: Uint8List(12));
        expect(plain, Uint8List(16));
      });
    });
  });
}
