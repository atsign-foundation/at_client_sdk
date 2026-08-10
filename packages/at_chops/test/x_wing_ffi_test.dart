@Tags(['ffi'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
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

    setUp(() {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlKemSupported) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }
    });

    test(
        'FFI key generation matches the pure-Dart public key for the same seed',
        () async {
      final ffi = XWingFfiAlgo.fromLib(lib!);
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
      final ffi = XWingFfiAlgo.fromLib(lib!);
      final ss = await ffi.decapsulate(seed, ct);
      expect(ss, equals(expectedSs));
    });

    test('FFI encapsulate/decapsulate round-trip agrees on the shared secret',
        () async {
      final ffi = XWingFfiAlgo.fromLib(lib!);
      final kp = await ffi.generateKeyPair();
      final enc = await ffi.encapsulate(kp.publicKey);
      expect(enc.ciphertext.length, XWingFfiAlgo.ciphertextLength);
      expect(enc.sharedSecret.length, 32);
      final ss = await ffi.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, equals(enc.sharedSecret));
    });

    test('interop: FFI encapsulates, pure-Dart decapsulates', () async {
      final ffi = XWingFfiAlgo.fromLib(lib!);
      final kp = await ffi.generateKeyPair();
      final enc = await ffi.encapsulate(kp.publicKey);
      final ss = await XWingPureDartAlgo.instance
          .decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, equals(enc.sharedSecret));
    });

    test('interop: pure-Dart encapsulates, FFI decapsulates', () async {
      final ffi = XWingFfiAlgo.fromLib(lib!);
      final kp = await ffi.generateKeyPair();
      final enc = await XWingPureDartAlgo.instance.encapsulate(kp.publicKey);
      final ss = await ffi.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, equals(enc.sharedSecret));
    });

    test(
        'a tampered ciphertext decapsulates to a different secret, not an error',
        () async {
      final ffi = XWingFfiAlgo.fromLib(lib!);
      final kp = await ffi.generateKeyPair();
      final enc = await ffi.encapsulate(kp.publicKey);
      final tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;
      final ss = await ffi.decapsulate(kp.secretKey, tampered);
      expect(ss.length, 32);
      expect(ss, isNot(equals(enc.sharedSecret)));
    });
  });
}
