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

    AesCtrFfiAlgo makeAlgo(AESKey key) {
      if (lib == null) fail('libcrypto not available on this host');
      return AesCtrFfiAlgo.fromLib(lib, key);
    }

    group('round-trip encrypt→decrypt at 16, 24, and 32-byte keys', () {
      for (final len in [16, 24, 32]) {
        test('${len * 8}-bit key', () async {
          final AESKey key = AESKey.generate(len);
          final AesCtrFfiAlgo algo = makeAlgo(key);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain =
              Uint8List.fromList(utf8.encode('hello, alice'));

          final Uint8List encrypted = await algo.encrypt(plain, iv: iv);
          final Uint8List decrypted = await algo.decrypt(encrypted, iv: iv);
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
          final AESKey key = AESKey.generate(len);
          final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
          final AESEncryptionAlgo pureAlgo = AESEncryptionAlgo(key);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain = Uint8List.fromList(utf8.encode('ffi→pure'));

          final Uint8List encrypted = await ffiAlgo.encrypt(plain, iv: iv);
          final Uint8List decrypted = await pureAlgo.decrypt(encrypted, iv: iv);
          expect(utf8.decode(decrypted), 'ffi→pure');
        });

        test('${len * 8}-bit: pure-Dart encrypts, FFI decrypts', () async {
          final AESKey key = AESKey.generate(len);
          final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
          final AESEncryptionAlgo pureAlgo = AESEncryptionAlgo(key);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain = Uint8List.fromList(utf8.encode('pure→ffi'));

          final Uint8List encrypted = await pureAlgo.encrypt(plain, iv: iv);
          final Uint8List decrypted = await ffiAlgo.decrypt(encrypted, iv: iv);
          expect(utf8.decode(decrypted), 'pure→ffi');
        });

        test('${len * 8}-bit: both backends emit the same ciphertext',
            () async {
          final AESKey key = AESKey.generate(len);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain =
              Uint8List.fromList(utf8.encode('byte-for-byte'));

          expect(await makeAlgo(key).encrypt(plain, iv: iv),
              await AESEncryptionAlgo(key).encrypt(plain, iv: iv),
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
        final AESKey key = AESKey(base64Encode(
            Uint8List.fromList(List.generate(32, (i) => i))));
        final InitialisationVector iv = InitialisationVector(
            Uint8List.fromList([
          0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]));
        final Uint8List plain =
            Uint8List.fromList(utf8.encode('low64 carry boundary'));

        final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
        final AESEncryptionAlgo pureAlgo = AESEncryptionAlgo(key);

        final Uint8List ffiEncrypted = await ffiAlgo.encrypt(plain, iv: iv);
        final Uint8List pureEncrypted = await pureAlgo.encrypt(plain, iv: iv);

        expect(ffiEncrypted.length, 32);
        expect(hexOf(ffiEncrypted),
            '076fa7bcf8050ca8d06c0584d76a030c519db4dc61384e8bfae479c20bf02d80');
        expect(hexOf(pureEncrypted),
            '076fa7bcf8050ca8d06c0584d76a030c519db4dc61384e8bfae479c20bf02d80');
        expect(await pureAlgo.decrypt(ffiEncrypted, iv: iv), plain);
        expect(await ffiAlgo.decrypt(pureEncrypted, iv: iv), plain);
      });
    });

    group('Lengths (0, 1, 15, 16, 17, 4095)', () {
      for (final len in [0, 1, 15, 16, 17, 4095]) {
        test('$len bytes round-trips and ciphertext has PKCS7 length',
            () async {
          final AESKey key = AESKey.generate(32);
          final AesCtrFfiAlgo algo = makeAlgo(key);
          final InitialisationVector iv = InitialisationVector.random(16);
          final Uint8List plain = Uint8List(len);
          // PKCS7 padding length logic:
          final int expectedLen = len + (16 - (len % 16));

          final Uint8List encrypted = await algo.encrypt(plain, iv: iv);
          expect(encrypted.length, expectedLen);

          final Uint8List decrypted = await algo.decrypt(encrypted, iv: iv);
          expect(decrypted, plain);
        });
      }
    });

    test('wrong key throws AtDecryptionException or produces wrong result',
        () async {
      final AESKey key1 = AESKey.generate(32);
      final AESKey key2 = AESKey.generate(32);
      final InitialisationVector iv = InitialisationVector.random(16);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));

      final Uint8List encrypted = await makeAlgo(key1).encrypt(plain, iv: iv);
      try {
        final Uint8List decrypted =
            await makeAlgo(key2).decrypt(encrypted, iv: iv);
        expect(decrypted, isNot(plain));
      } on AtDecryptionException catch (_) {
        // Expected if padding removal fails
      } on ArgumentError catch (_) {
        // Expected if padding removal fails
      }
    });

    test('wrong IV throws AtDecryptionException or produces wrong result',
        () async {
      final AESKey key = AESKey.generate(32);
      final AesCtrFfiAlgo algo = makeAlgo(key);
      final InitialisationVector iv1 = InitialisationVector.random(16);
      final InitialisationVector iv2 = InitialisationVector.random(16);
      final Uint8List plain = Uint8List.fromList(utf8.encode('secret'));

      final Uint8List encrypted = await algo.encrypt(plain, iv: iv1);
      try {
        final Uint8List decrypted = await algo.decrypt(encrypted, iv: iv2);
        expect(decrypted, isNot(plain));
      } on AtDecryptionException catch (_) {
        // Expected if padding removal fails
      } on ArgumentError catch (_) {
        // Expected if padding removal fails
      }
    });

    test('a nonce of the wrong length is rejected in both directions',
        () async {
      final AESKey key = AESKey.generate(32);
      final AesCtrFfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList([1, 2, 3]);
      await expectLater(
          algo.encrypt(plain), throwsA(isA<AtEncryptionException>()));
      await expectLater(
          algo.encrypt(plain, iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));
      await expectLater(
          algo.decrypt(plain), throwsA(isA<AtDecryptionException>()));
      await expectLater(
          algo.decrypt(plain, iv: InitialisationVector.random(12)),
          throwsA(isA<AtDecryptionException>()));
    });

    /// The backends are interchangeable for a 16-byte IV and for no other
    /// length, so a caller handed an IV it did not choose gets an outcome
    /// that depends on whether the host has libcrypto. Pinned here so the
    /// dartdoc on [AtPqc.aesCtr] cannot drift away from the behaviour.
    group('a non-16-byte IV is where the two backends part company', () {
      for (final int len in <int>[8, 12, 15]) {
        test('$len-byte IV: pure-Dart accepts, FFI rejects', () async {
          final AESKey key = AESKey.generate(32);
          final InitialisationVector iv = InitialisationVector.random(len);
          final Uint8List plain = Uint8List.fromList(utf8.encode('short iv'));

          expect(
              await AESEncryptionAlgo(key).encrypt(plain, iv: iv), isNotEmpty,
              reason: 'the pure-Dart path right-pads a short IV into the '
                  'counter block rather than rejecting it');
          await expectLater(makeAlgo(key).encrypt(plain, iv: iv),
              throwsA(isA<AtEncryptionException>()));
          await expectLater(makeAlgo(key).decrypt(plain, iv: iv),
              throwsA(isA<AtDecryptionException>()),
              reason: 'the decrypt direction rejects with its own sibling '
                  'exception, not AtEncryptionException');
        });
      }

      test('16 bytes is the length on which they agree', () async {
        final AESKey key = AESKey.generate(32);
        final InitialisationVector iv = InitialisationVector.random(16);
        final Uint8List plain = Uint8List.fromList(utf8.encode('short iv'));

        expect(await makeAlgo(key).encrypt(plain, iv: iv),
            await AESEncryptionAlgo(key).encrypt(plain, iv: iv),
            reason: 'the control for the divergence tests above: without it '
                'they would pass against a backend that rejected every IV');
      });
    });

    test('a key that is not 16/24/32 bytes throws AtEncryptionException',
        () async {
      final AesCtrFfiAlgo algo = makeAlgo(AESKey.generate(15));
      await expectLater(
          algo.encrypt(Uint8List.fromList([1]),
              iv: InitialisationVector.random(16)),
          throwsA(isA<AtEncryptionException>()));
    });
  });
}
