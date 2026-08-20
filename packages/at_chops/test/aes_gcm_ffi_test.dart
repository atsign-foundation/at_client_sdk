@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:test/test.dart';

const int _nonceLen = AesGcm256FfiAlgo.nonceLength;
const int _tagLen = AesGcm256FfiAlgo.tagLength;

Uint8List _hex(String s) {
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('AES-256-GCM FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);

    setUpAll(() {
      if (lib != null) {
        // ignore: avoid_print
        print('libcrypto loaded from: ${loadedPath.toString()}');
      }
    });

    AesGcm256FfiAlgo makeAlgo(AESKey key) {
      if (lib == null) fail('libcrypto not available on this host');
      return AesGcm256FfiAlgo.fromLib(lib, key);
    }

    test('encrypt then decrypt returns the plaintext', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello, alice'));

      final Uint8List encrypted = await algo.encrypt(plain);
      // nonce(12) || ciphertext || tag(16)
      expect(encrypted.length, _nonceLen + plain.length + _tagLen);

      final Uint8List decrypted = await algo.decrypt(encrypted);
      expect(utf8.decode(decrypted), 'hello, alice');
    });

    test('every encryption draws a fresh nonce', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList(utf8.encode('same plaintext'));
      final Set<String> seenNonces = <String>{};
      for (int i = 0; i < 64; i++) {
        final Uint8List encrypted = await algo.encrypt(plain);
        final String nonce = base64Encode(encrypted.sublist(0, _nonceLen));
        expect(seenNonces.add(nonce), isTrue,
            reason: 'nonce repeated after ${seenNonces.length} encryptions');
      }
    });

    test('supplying an IV is rejected — the algorithm owns the nonce',
        () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList(utf8.encode('x'));

      await expectLater(
          algo.encrypt(plain, iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));

      final Uint8List encrypted = await algo.encrypt(plain);
      await expectLater(
          algo.decrypt(encrypted, iv: InitialisationVector.random(12)),
          throwsA(isA<AtDecryptionException>()));
    });

    test('empty plaintext round-trips (nonce + tag only output)', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);

      final Uint8List encrypted = await algo.encrypt(Uint8List(0));
      expect(encrypted.length, _nonceLen + _tagLen);

      final Uint8List decrypted = await algo.decrypt(encrypted);
      expect(decrypted, isEmpty);
    });

    test('tampered nonce throws AtDecryptionException', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));
      final Uint8List encrypted = await algo.encrypt(plain);

      final Uint8List tampered = Uint8List.fromList(encrypted);
      tampered[0] ^= 0x01;
      await expectLater(
          algo.decrypt(tampered), throwsA(isA<AtDecryptionException>()));
    });

    test('tampered ciphertext throws AtDecryptionException', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final Uint8List encrypted = await algo.encrypt(plain);

      final Uint8List tampered = Uint8List.fromList(encrypted);
      tampered[_nonceLen] ^= 0x01;
      await expectLater(
          algo.decrypt(tampered), throwsA(isA<AtDecryptionException>()));
    });

    test('tampered tag throws AtDecryptionException', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final Uint8List encrypted = await algo.encrypt(plain);

      final Uint8List tampered = Uint8List.fromList(encrypted);
      tampered[encrypted.length - 1] ^= 0x01;
      await expectLater(
          algo.decrypt(tampered), throwsA(isA<AtDecryptionException>()));
    });

    test('wrong key throws AtDecryptionException', () async {
      final AESKey key1 = AESKey.generate(32);
      final AESKey key2 = AESKey.generate(32);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));

      final Uint8List encrypted = await makeAlgo(key1).encrypt(plain);
      await expectLater(makeAlgo(key2).decrypt(encrypted),
          throwsA(isA<AtDecryptionException>()));
    });

    test('input shorter than nonce + tag is rejected', () async {
      final AesGcm256FfiAlgo algo = makeAlgo(AESKey.generate(32));
      await expectLater(algo.decrypt(Uint8List(_nonceLen + _tagLen - 1)),
          throwsA(isA<AtDecryptionException>()));
    });

    test('a key that is not 256 bits is rejected', () async {
      final AesGcm256FfiAlgo algo = makeAlgo(AESKey.generate(16));
      await expectLater(algo.encrypt(Uint8List.fromList([1])),
          throwsA(isA<AtEncryptionException>()));
    });

    group('AAD', () {
      test('round-trips when AAD matches', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo algo = makeAlgo(key);
        final Uint8List plain = Uint8List.fromList(utf8.encode('secret body'));
        final List<int> aad = utf8.encode('authenticated header');

        final Uint8List encrypted = await algo.encrypt(plain, aad: aad);
        final Uint8List decrypted = await algo.decrypt(encrypted, aad: aad);
        expect(utf8.decode(decrypted), 'secret body');
      });

      test('mismatched AAD throws AtDecryptionException', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo algo = makeAlgo(key);
        final Uint8List plain = Uint8List.fromList(utf8.encode('secret body'));

        final Uint8List encrypted =
            await algo.encrypt(plain, aad: utf8.encode('header-A'));
        await expectLater(
            algo.decrypt(encrypted, aad: utf8.encode('header-B')),
            throwsA(isA<AtDecryptionException>()));
      });
    });

    group('explicit-nonce API (single-use keys and KAT vectors only)', () {
      test('a nonce of the wrong length is rejected', () async {
        final AesGcm256FfiAlgo algo = makeAlgo(AESKey.generate(32));
        final Uint8List plain = Uint8List.fromList([1, 2, 3]);
        await expectLater(
            algo.encryptWithNonce(plain, nonce: Uint8List(16)),
            throwsA(isA<AtEncryptionException>()));
        await expectLater(
            algo.decryptWithNonce(Uint8List(_tagLen + 1),
                nonce: Uint8List(16)),
            throwsA(isA<AtDecryptionException>()));
      });

      test('NIST GCM vector: case 13 (zero key/nonce, empty plaintext)',
          () async {
        // Same vector used in the pure-Dart test.
        final AESKey key = AESKey(base64Encode(Uint8List(32)));
        final AesGcm256FfiAlgo algo = makeAlgo(key);

        final Uint8List out =
            await algo.encryptWithNonce(Uint8List(0), nonce: Uint8List(12));
        expect(out, _hex('530f8afbc74536b9a963b4f1c4cb738b'));
      });

      test('NIST GCM vector: case 14 (zero key/nonce, 16-byte zero plaintext)',
          () async {
        final AESKey key = AESKey(base64Encode(Uint8List(32)));
        final AesGcm256FfiAlgo algo = makeAlgo(key);

        final Uint8List out =
            await algo.encryptWithNonce(Uint8List(16), nonce: Uint8List(12));
        expect(
            out,
            _hex('cea7403d4d606b6e074ec5d3baf39d18'
                'd0d1c8a799996bf0265b98b5d48ab919'));

        final Uint8List plain =
            await algo.decryptWithNonce(out, nonce: Uint8List(12));
        expect(plain, Uint8List(16));
      });
    });

    group('FFI / pure-Dart interop', () {
      test('FFI encrypts, pure-Dart decrypts', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo ffiAlgo = makeAlgo(key);
        final AesGcm256EncryptionAlgo pureAlgo = AesGcm256EncryptionAlgo(key);
        final Uint8List plain = Uint8List.fromList(utf8.encode('ffi→pure'));

        final Uint8List encrypted = await ffiAlgo.encrypt(plain);
        final Uint8List decrypted = await pureAlgo.decrypt(encrypted);
        expect(utf8.decode(decrypted), 'ffi→pure');
      });

      test('pure-Dart encrypts, FFI decrypts', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo ffiAlgo = makeAlgo(key);
        final AesGcm256EncryptionAlgo pureAlgo = AesGcm256EncryptionAlgo(key);
        final Uint8List plain = Uint8List.fromList(utf8.encode('pure→ffi'));

        final Uint8List encrypted = await pureAlgo.encrypt(plain);
        final Uint8List decrypted = await ffiAlgo.decrypt(encrypted);
        expect(utf8.decode(decrypted), 'pure→ffi');
      });
    });
  });
}
