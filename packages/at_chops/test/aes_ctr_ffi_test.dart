@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:test/test.dart';

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
      test('FFI encrypts, pure-Dart decrypts', () async {
        final AESKey key = AESKey.generate(32);
        final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
        final AESEncryptionAlgo pureAlgo = AESEncryptionAlgo(key);
        final InitialisationVector iv = InitialisationVector.random(16);
        final Uint8List plain = Uint8List.fromList(utf8.encode('ffi→pure'));

        final Uint8List encrypted = await ffiAlgo.encrypt(plain, iv: iv);
        final Uint8List decrypted = await pureAlgo.decrypt(encrypted, iv: iv);
        expect(utf8.decode(decrypted), 'ffi→pure');
      });

      test('pure-Dart encrypts, FFI decrypts', () async {
        final AESKey key = AESKey.generate(32);
        final AesCtrFfiAlgo ffiAlgo = makeAlgo(key);
        final AESEncryptionAlgo pureAlgo = AESEncryptionAlgo(key);
        final InitialisationVector iv = InitialisationVector.random(16);
        final Uint8List plain = Uint8List.fromList(utf8.encode('pure→ffi'));

        final Uint8List encrypted = await pureAlgo.encrypt(plain, iv: iv);
        final Uint8List decrypted = await ffiAlgo.decrypt(encrypted, iv: iv);
        expect(utf8.decode(decrypted), 'pure→ffi');
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

    test('a nonce of the wrong length is rejected', () async {
      final AESKey key = AESKey.generate(32);
      final AesCtrFfiAlgo algo = makeAlgo(key);
      final Uint8List plain = Uint8List.fromList([1, 2, 3]);
      await expectLater(
          algo.encrypt(plain), throwsA(isA<AtEncryptionException>()));
      await expectLater(
          algo.encrypt(plain, iv: InitialisationVector.random(12)),
          throwsA(isA<AtEncryptionException>()));
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
