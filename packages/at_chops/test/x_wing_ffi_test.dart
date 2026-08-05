@Tags(['ffi'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/src/algorithm/spec/ml_kem_768_spec.dart';
import 'package:test/test.dart';

import 'x_wing_test_vectors.dart';

void main() {
  group('X-Wing FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);
    final bool mlKemSupported = lib != null && libCryptoSupportsMlKem768(lib);

    final seed = XWingVector1.seed;
    final ct = XWingVector1.ct;
    final expectedSs = XWingVector1.expectedSs;

    setUpAll(() {
      if (lib != null) {
        // ignore: avoid_print
        print('libcrypto loaded from: ${loadedPath.toString()}');
      }
    });

    test(
        'FFI key generation matches the pure-Dart public key for the same seed',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final ffi = XWingFfiAlgo.fromLib(lib);
      final ffiKp = await ffi.generateKeyPair(seed);
      final pureKp = await XWingPureDartAlgo.instance.generateKeyPair(seed);
      // Deterministic from the seed across both backends — proves the FFI
      // ML-KEM seeded keygen (d || z import) and the X25519 public derivation
      // are byte-correct.
      expect(ffiKp.publicKey, equals(pureKp.publicKey));
      expect(ffiKp.publicKey.length, XWingFfiAlgo.publicKeyLength);
      expect(ffiKp.secretKey, equals(seed));
    });

    test('FFI decapsulates the draft vector ciphertext to the vector secret',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final ffi = XWingFfiAlgo.fromLib(lib);
      final ss = await ffi.decapsulate(seed, ct);
      expect(ss, equals(expectedSs));
    });

    test('FFI encapsulate/decapsulate round-trip agrees on the shared secret',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final ffi = XWingFfiAlgo.fromLib(lib);
      final kp = await ffi.generateKeyPair();
      final enc = await ffi.encapsulate(kp.publicKey);
      expect(enc.ciphertext.length, XWingFfiAlgo.ciphertextLength);
      expect(enc.sharedSecret.length, 32);
      final ss = await ffi.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, equals(enc.sharedSecret));
    });

    test('interop: FFI encapsulates, pure-Dart decapsulates', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final ffi = XWingFfiAlgo.fromLib(lib);
      final kp = await ffi.generateKeyPair();
      final enc = await ffi.encapsulate(kp.publicKey);
      final ss = await XWingPureDartAlgo.instance
          .decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, equals(enc.sharedSecret));
    });

    test('interop: pure-Dart encapsulates, FFI decapsulates', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final ffi = XWingFfiAlgo.fromLib(lib);
      final kp = await ffi.generateKeyPair();
      final enc = await XWingPureDartAlgo.instance.encapsulate(kp.publicKey);
      final ss = await ffi.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, equals(enc.sharedSecret));
    });

    test(
        'a tampered ciphertext decapsulates to a different secret, not an error',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final ffi = XWingFfiAlgo.fromLib(lib);
      final kp = await ffi.generateKeyPair();
      final enc = await ffi.encapsulate(kp.publicKey);
      final tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;
      final ss = await ffi.decapsulate(kp.secretKey, tampered);
      expect(ss.length, 32);
      expect(ss, isNot(equals(enc.sharedSecret)));
    });

    // Pins each checkOutputLength call in _combine to its own constant and
    // label — MlKem768Sizes.sharedSecretBytes and
    // XWingSizes.x25519ComponentLength are both 32 today, so a round-trip
    // test alone can't tell them apart; these prove the wiring directly.
    test('wrong-length ssM is rejected against the ML-KEM-768 label', () {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      final ffi = XWingFfiAlgo.fromLib(lib);
      expect(
          () => ffi.combineForTesting(
              Uint8List(31), Uint8List(32), Uint8List(32), Uint8List(1216)),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('ML-KEM-768 shared secret component'))));
    });

    test('wrong-length ssX is rejected against the X25519 label', () {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      final ffi = XWingFfiAlgo.fromLib(lib);
      expect(
          () => ffi.combineForTesting(
              Uint8List(32), Uint8List(33), Uint8List(32), Uint8List(1216)),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('X25519 shared secret component'))));
    });

    group('_assemblePublicKey / _assembleCiphertext length guards and offsets',
        () {
      // Distinct fill values so a swapped-setRange or offset-shift bug can't
      // slip past the equality checks below.
      final mlKemPublicKey = Uint8List(MlKem768Sizes.publicKeyBytes)
        ..fillRange(0, MlKem768Sizes.publicKeyBytes, 0xAA);
      final x25519Public = Uint8List(32)..fillRange(0, 32, 0xBB);
      final ctM = Uint8List(MlKem768Sizes.ciphertextBytes)
        ..fillRange(0, MlKem768Sizes.ciphertextBytes, 0xAA);
      final ctX = Uint8List(32)..fillRange(0, 32, 0xBB);

      test('wrong-length ML-KEM public key is rejected', () {
        if (lib == null) {
          fail('libcrypto not available on this host');
        }
        final ffi = XWingFfiAlgo.fromLib(lib);
        expect(
            () => ffi.assemblePublicKeyForTesting(
                Uint8List(MlKem768Sizes.publicKeyBytes - 1), x25519Public),
            throwsA(isA<StateError>()
                .having((e) => e.message, 'message',
                    contains('ML-KEM-768 generateKeyPair'))
                .having((e) => e.message, 'message', contains('public key'))));
      });

      test(
          'correct-length inputs assemble the public key with components at '
          'the right offsets', () {
        if (lib == null) {
          fail('libcrypto not available on this host');
        }
        final ffi = XWingFfiAlgo.fromLib(lib);
        final publicKey =
            ffi.assemblePublicKeyForTesting(mlKemPublicKey, x25519Public);
        expect(publicKey.length, XWingFfiAlgo.publicKeyLength);
        expect(
            publicKey.sublist(0, MlKem768Sizes.publicKeyBytes), mlKemPublicKey);
        expect(publicKey.sublist(MlKem768Sizes.publicKeyBytes), x25519Public);
      });

      test('wrong-length ML-KEM ciphertext is rejected', () {
        if (lib == null) {
          fail('libcrypto not available on this host');
        }
        final ffi = XWingFfiAlgo.fromLib(lib);
        expect(
            () => ffi.assembleCiphertextForTesting(
                Uint8List(MlKem768Sizes.ciphertextBytes + 1), ctX),
            throwsA(isA<StateError>()
                .having((e) => e.message, 'message',
                    contains('ML-KEM-768 encapsulate'))
                .having((e) => e.message, 'message', contains('ciphertext'))));
      });

      test(
          'correct-length inputs assemble the ciphertext with components at '
          'the right offsets', () {
        if (lib == null) {
          fail('libcrypto not available on this host');
        }
        final ffi = XWingFfiAlgo.fromLib(lib);
        final ciphertext = ffi.assembleCiphertextForTesting(ctM, ctX);
        expect(ciphertext.length, XWingFfiAlgo.ciphertextLength);
        expect(ciphertext.sublist(0, MlKem768Sizes.ciphertextBytes), ctM);
        expect(ciphertext.sublist(MlKem768Sizes.ciphertextBytes), ctX);
      });
    });
  });
}
