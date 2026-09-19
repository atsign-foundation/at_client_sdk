@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:test/test.dart';

String hexOf(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('AES-CTR FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);

    setUpAll(() {
      if (lib != null) {
        // ignore: avoid_print
        print('libcrypto loaded from: ${loadedPath.toString()}');
      }
    });

    AesCtrFfiAlgo makeAlgo(Uint8List key) {
      if (lib == null) fail('libcrypto not available on this host');
      return AesCtrFfiAlgo.fromLib(lib, key.length);
    }

    group('round-trip encrypt→decrypt at 16, 24, and 32-byte keys', () {
      for (final len in [16, 24, 32]) {
        test('${len * 8}-bit key', () async {
          final Uint8List key = AesCtrEncryptionAlgo(len).generateKey();
          final AesCtrFfiAlgo algo = makeAlgo(key);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain =
              Uint8List.fromList(utf8.encode('hello, alice'));

          final Uint8List encrypted = await algo.encrypt(plain, key, iv: iv);
          final Uint8List decrypted = await algo.decrypt(encrypted, key, iv: iv);
          expect(utf8.decode(decrypted), 'hello, alice');
        });
      }
    });

    group('FFI / pure-Dart interop (padding-parity guard)', () {
      // Every key length AesCtrFactory accepts, not just 256-bit: accepting
      // 16 and 24 is what keeps a pure-Dart caller working after it resolves
      // to FFI, so those are the lengths the parity claim is about.
      for (final int len in <int>[16, 24, 32]) {
        test('${len * 8}-bit: FFI encrypts, pure-Dart decrypts', () async {
          final Uint8List key = AesCtrEncryptionAlgo(len).generateKey();
          final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
          final AesCtrEncryptionAlgo pureAlgo = AesCtrEncryptionAlgo(key.length);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain = Uint8List.fromList(utf8.encode('ffi→pure'));

          final Uint8List encrypted = await ffiAlgo.encrypt(plain, key, iv: iv);
          final Uint8List decrypted = await pureAlgo.decrypt(encrypted, key, iv: iv);
          expect(utf8.decode(decrypted), 'ffi→pure');
        });

        test('${len * 8}-bit: pure-Dart encrypts, FFI decrypts', () async {
          final Uint8List key = AesCtrEncryptionAlgo(len).generateKey();
          final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
          final AesCtrEncryptionAlgo pureAlgo = AesCtrEncryptionAlgo(key.length);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain = Uint8List.fromList(utf8.encode('pure→ffi'));

          final Uint8List encrypted = await pureAlgo.encrypt(plain, key, iv: iv);
          final Uint8List decrypted = await ffiAlgo.decrypt(encrypted, key, iv: iv);
          expect(utf8.decode(decrypted), 'pure→ffi');
        });

        test('${len * 8}-bit: both backends emit the same ciphertext',
            () async {
          final Uint8List key = AesCtrEncryptionAlgo(len).generateKey();
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain =
              Uint8List.fromList(utf8.encode('byte-for-byte'));

          expect(await makeAlgo(key).encrypt(plain, key, iv: iv),
              await AesCtrEncryptionAlgo(key.length).encrypt(plain, key, iv: iv),
              reason: 'a cross-decrypt still passes if both backends are '
                  'wrong in the same way; this does not');
        });
      }

      // The IV's low 8 bytes are all 0xFF, so block 1 encrypts with the
      // counter at 2^64 - 1 and block 2 carries into the IV's high half. A
      // backend that increments only the low 64 bits of the counter block
      // encrypts block 2 differently, and the equality and hex pins below
      // catch that on either side.
      test('multi-block parity across the low64(IV) carry boundary', () async {
        final Uint8List key =
            Uint8List.fromList(List.generate(32, (i) => i));
        final InitialisationVector iv = InitialisationVector(
            Uint8List.fromList([
          0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]));
        final Uint8List plain =
            Uint8List.fromList(utf8.encode('low64 carry boundary'));

        final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
        final AesCtrEncryptionAlgo pureAlgo = AesCtrEncryptionAlgo(key.length);

        final Uint8List ffiEncrypted = await ffiAlgo.encrypt(plain, key, iv: iv);
        final Uint8List pureEncrypted = await pureAlgo.encrypt(plain, key, iv: iv);

        expect(ffiEncrypted.length, 32);
        expect(hexOf(ffiEncrypted),
            '076fa7bcf8050ca8d06c0584d76a030c519db4dc61384e8bfae479c20bf02d80');
        expect(hexOf(pureEncrypted),
            '076fa7bcf8050ca8d06c0584d76a030c519db4dc61384e8bfae479c20bf02d80');
        expect(await pureAlgo.decrypt(ffiEncrypted, key, iv: iv), plain);
        expect(await ffiAlgo.decrypt(pureEncrypted, key, iv: iv), plain);
      });
    });

    group('Lengths (0, 1, 15, 16, 17, 4095)', () {
      for (final len in [0, 1, 15, 16, 17, 4095]) {
        test('$len bytes round-trips and ciphertext has PKCS7 length',
            () async {
          final Uint8List key = AesCtrEncryptionAlgo(32).generateKey();
          final AesCtrFfiAlgo algo = makeAlgo(key);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain = Uint8List(len);
          // PKCS7 padding length logic:
          final int expectedLen = len + (16 - (len % 16));

          final Uint8List encrypted = await algo.encrypt(plain, key, iv: iv);
          expect(encrypted.length, expectedLen);

          final Uint8List decrypted = await algo.decrypt(encrypted, key, iv: iv);
          expect(decrypted, plain);
        });
      }
    });

    test('wrong key throws AtDecryptionException or produces wrong result',
        () async {
      final Uint8List key1 = AesCtrEncryptionAlgo(32).generateKey();
      final Uint8List key2 = AesCtrEncryptionAlgo(32).generateKey();
      final InitialisationVector iv = InitialisationVector.random(16);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));

      final Uint8List encrypted =
          await makeAlgo(key1).encrypt(plain, key1, iv: iv);
      try {
        final Uint8List decrypted =
            await makeAlgo(key2).decrypt(encrypted, key2, iv: iv);
        expect(decrypted, isNot(plain));
      } on AtDecryptionException catch (_) {
        // Expected if padding removal fails
      } on ArgumentError catch (_) {
        // Expected if padding removal fails
      }
    });

    test('wrong IV throws AtDecryptionException or produces wrong result',
        () async {
      final Uint8List key = AesCtrEncryptionAlgo(32).generateKey();
      final AesCtrFfiAlgo algo = makeAlgo(key);
      final InitialisationVector iv1 = InitialisationVector.random(16);
      final InitialisationVector iv2 = InitialisationVector.random(16);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));

      final Uint8List encrypted = await algo.encrypt(plain, key, iv: iv1);
      try {
        final Uint8List decrypted = await algo.decrypt(encrypted, key, iv: iv2);
        expect(decrypted, isNot(plain));
      } on AtDecryptionException catch (_) {
        // Expected if padding removal fails
      } on ArgumentError catch (_) {
        // Expected if padding removal fails
      }
    });

    test('a nonce of the wrong length is rejected in both directions',
        () async {
      final Uint8List key = AesCtrEncryptionAlgo(32).generateKey();
      final AesCtrFfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList([1, 2, 3]);
      await expectLater(
          algo.encrypt(plain, key, iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));
      await expectLater(
          algo.decrypt(plain, key, iv: InitialisationVector.random(12)),
          throwsA(isA<AtDecryptionException>()));
    });

    /// 3.x is where the backends parted company on IV length: the pure-Dart
    /// path substituted zeroes for a missing IV and right-padded a short one,
    /// while the FFI path rejected both. 4.0.0 closed that — `iv` is required
    /// and both backends require exactly 16 bytes — so the outcome no longer
    /// depends on whether the host has libcrypto. Pinned here because that is
    /// the property, not an implementation detail of either backend.
    group('a non-16-byte IV is rejected by BOTH backends alike', () {
      for (final int len in <int>[8, 12, 15]) {
        test('$len-byte IV: neither backend accepts it', () async {
          final Uint8List key = AesCtrEncryptionAlgo(32).generateKey();
          final InitialisationVector iv = InitialisationVector.random(len);
          final Uint8List plain = Uint8List.fromList(utf8.encode('short iv'));

          await expectLater(
              AesCtrEncryptionAlgo(32).encrypt(plain, key, iv: iv),
              throwsA(isA<AtEncryptionException>()),
              reason: 'the pure-Dart path no longer right-pads a short IV');
          await expectLater(makeAlgo(key).encrypt(plain, key, iv: iv),
              throwsA(isA<AtEncryptionException>()));
          await expectLater(makeAlgo(key).decrypt(plain, key, iv: iv),
              throwsA(isA<AtDecryptionException>()),
              reason: 'the decrypt direction rejects with its own sibling '
                  'exception, not AtEncryptionException');
        });
      }

      test('16 bytes is the length on which they agree', () async {
        final Uint8List key = AesCtrEncryptionAlgo(32).generateKey();
        final InitialisationVector iv = InitialisationVector.random(16);
        final Uint8List plain = Uint8List.fromList(utf8.encode('short iv'));

        expect(await makeAlgo(key).encrypt(plain, key, iv: iv),
            await AesCtrEncryptionAlgo(32).encrypt(plain, key, iv: iv),
            reason: 'the control for the rejection tests above: without it '
                'they would pass against a backend that rejected every IV');
      });
    });

    test('a key length that is not 16/24/32 throws AtEncryptionException', () {
      // The length is a constructor argument now, so this fails before any
      // key or plaintext is in hand rather than at the first encrypt.
      expect(() => makeAlgo(Uint8List(15)),
          throwsA(isA<AtEncryptionException>()));
    });
  });
}
