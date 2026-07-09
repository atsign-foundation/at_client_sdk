@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:test/test.dart';

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
      final InitialisationVector iv = InitialisationVector.random(12);
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello, alice'));

      final Uint8List encrypted = await algo.encrypt(plain, iv: iv);
      expect(encrypted.length, plain.length + AesGcm256FfiAlgo.tagLength);

      final Uint8List decrypted = await algo.decrypt(encrypted, iv: iv);
      expect(utf8.decode(decrypted), 'hello, alice');
    });

    test('empty plaintext round-trips (tag only output)', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final InitialisationVector iv = InitialisationVector.random(12);

      final Uint8List encrypted = await algo.encrypt(Uint8List(0), iv: iv);
      expect(encrypted.length, AesGcm256FfiAlgo.tagLength);

      final Uint8List decrypted = await algo.decrypt(encrypted, iv: iv);
      expect(decrypted, isEmpty);
    });

    test('tampered ciphertext throws AtDecryptionException', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final InitialisationVector iv = InitialisationVector.random(12);
      final Uint8List plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final Uint8List encrypted = await algo.encrypt(plain, iv: iv);

      final Uint8List tampered = Uint8List.fromList(encrypted);
      tampered[0] ^= 0x01;
      await expectLater(algo.decrypt(tampered, iv: iv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('tampered tag throws AtDecryptionException', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final InitialisationVector iv = InitialisationVector.random(12);
      final Uint8List plain = Uint8List.fromList(utf8.encode('attack at dawn'));
      final Uint8List encrypted = await algo.encrypt(plain, iv: iv);

      final Uint8List tampered = Uint8List.fromList(encrypted);
      tampered[encrypted.length - 1] ^= 0x01;
      await expectLater(algo.decrypt(tampered, iv: iv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('wrong nonce throws AtDecryptionException', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final InitialisationVector iv = InitialisationVector.random(12);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));
      final Uint8List encrypted = await algo.encrypt(plain, iv: iv);

      final InitialisationVector otherIv = InitialisationVector.random(12);
      await expectLater(algo.decrypt(encrypted, iv: otherIv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('wrong key throws AtDecryptionException', () async {
      final AESKey key1 = AESKey.generate(32);
      final AESKey key2 = AESKey.generate(32);
      final InitialisationVector iv = InitialisationVector.random(12);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));

      final Uint8List encrypted = await makeAlgo(key1).encrypt(plain, iv: iv);
      await expectLater(makeAlgo(key2).decrypt(encrypted, iv: iv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('a nonce of the wrong length is rejected', () async {
      final AESKey key = AESKey.generate(32);
      final AesGcm256FfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList([1, 2, 3]);
      await expectLater(
          algo.encrypt(plain), throwsA(isA<AtEncryptionException>()));
      await expectLater(
          algo.encrypt(plain, iv: InitialisationVector.random(16)),
          throwsA(isA<AtEncryptionException>()));
    });

    test('a key that is not 256 bits is rejected', () async {
      final AesGcm256FfiAlgo algo = makeAlgo(AESKey.generate(16));
      await expectLater(
          algo.encrypt(Uint8List.fromList([1]),
              iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));
    });

    group('AAD', () {
      test('round-trips when AAD matches', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo algo = makeAlgo(key);
        final InitialisationVector iv = AtChopsUtil.generateRandomIV(12);
        final Uint8List plain = Uint8List.fromList(utf8.encode('secret body'));
        final List<int> aad = utf8.encode('authenticated header');

        final Uint8List encrypted = await algo.encrypt(plain, iv: iv, aad: aad);
        final Uint8List decrypted =
            await algo.decrypt(encrypted, iv: iv, aad: aad);
        expect(utf8.decode(decrypted), 'secret body');
      });

      test('mismatched AAD throws AtDecryptionException', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo algo = makeAlgo(key);
        final InitialisationVector iv = AtChopsUtil.generateRandomIV(12);
        final Uint8List plain = Uint8List.fromList(utf8.encode('secret body'));

        final Uint8List encrypted =
            await algo.encrypt(plain, iv: iv, aad: utf8.encode('header-A'));
        await expectLater(
            algo.decrypt(encrypted, iv: iv, aad: utf8.encode('header-B')),
            throwsA(isA<AtDecryptionException>()));
      });
    });

    group('FFI / pure-Dart interop', () {
      test('FFI encrypts, pure-Dart decrypts', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo ffiAlgo = makeAlgo(key);
        final AesGcm256EncryptionAlgo pureAlgo = AesGcm256EncryptionAlgo(key);
        final InitialisationVector iv = InitialisationVector.random(12);
        final Uint8List plain = Uint8List.fromList(utf8.encode('ffi→pure'));

        final Uint8List encrypted = await ffiAlgo.encrypt(plain, iv: iv);
        final Uint8List decrypted = await pureAlgo.decrypt(encrypted, iv: iv);
        expect(utf8.decode(decrypted), 'ffi→pure');
      });

      test('pure-Dart encrypts, FFI decrypts', () async {
        final AESKey key = AESKey.generate(32);
        final AesGcm256FfiAlgo ffiAlgo = makeAlgo(key);
        final AesGcm256EncryptionAlgo pureAlgo = AesGcm256EncryptionAlgo(key);
        final InitialisationVector iv = InitialisationVector.random(12);
        final Uint8List plain = Uint8List.fromList(utf8.encode('pure→ffi'));

        final Uint8List encrypted = await pureAlgo.encrypt(plain, iv: iv);
        final Uint8List decrypted = await ffiAlgo.decrypt(encrypted, iv: iv);
        expect(utf8.decode(decrypted), 'pure→ffi');
      });

      test('NIST GCM vector: case 13 (zero key/nonce, empty plaintext)',
          () async {
        // Same vector used in the pure-Dart test.
        final AESKey key = AESKey(base64Encode(Uint8List(32)));
        final AesGcm256FfiAlgo algo = makeAlgo(key);
        final InitialisationVector iv = InitialisationVector(Uint8List(12));

        final Uint8List out = await algo.encrypt(Uint8List(0), iv: iv);
        expect(out, _hex('530f8afbc74536b9a963b4f1c4cb738b'));
      });

      test('NIST GCM vector: case 14 (zero key/nonce, 16-byte zero plaintext)',
          () async {
        final AESKey key = AESKey(base64Encode(Uint8List(32)));
        final AesGcm256FfiAlgo algo = makeAlgo(key);
        final InitialisationVector iv = InitialisationVector(Uint8List(12));

        final Uint8List out = await algo.encrypt(Uint8List(16), iv: iv);
        expect(
            out,
            _hex('cea7403d4d606b6e074ec5d3baf39d18'
                'd0d1c8a799996bf0265b98b5d48ab919'));

        final Uint8List plain = await algo.decrypt(out, iv: iv);
        expect(plain, Uint8List(16));
      });
    });
  });
}
