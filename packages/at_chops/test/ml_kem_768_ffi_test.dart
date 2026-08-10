@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/src/algorithm/spec/ml_kem_768_spec.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);
    final bool mlKemSupported = lib != null && libCryptoSupportsMlKem768(lib);

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

    test('encapsulate/decapsulate round-trip within the FFI instance',
        () async {
      final algo = MlKem768FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      try {
        final enc = await algo.encapsulate(kp.publicKey);
        final Uint8List recovered =
            await algo.decapsulate(kp.secretKey, enc.ciphertext);
        expect(recovered, equals(enc.sharedSecret));
        expect(enc.sharedSecret.length, equals(32));
      } finally {
        algo.releaseKeyPair(kp);
      }
    });

    test('FFI sender can encapsulate against a pure-Dart-generated public key',
        () async {
      final MlKem768KeyPair kp = await MlKem768KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

      final ffiAlgo = MlKem768FfiAlgo.fromLib(lib!);
      final enc = await ffiAlgo.encapsulate(pub);

      // Recipient must use pure-Dart impl — FFI handles are non-serializable.
      final Uint8List recovered =
          await MlKem768PureDartAlgo.instance.decapsulate(priv, enc.ciphertext);
      expect(recovered, equals(enc.sharedSecret));
    });

    // The following pin the generateKeyPairFromSeed -> generateKeyPair([seed])
    // merge (used internally by XWingFfiAlgo) directly at the ML-KEM-768
    // level, rather than only transitively through X-Wing.
    group('seeded generateKeyPair (merged from generateKeyPairFromSeed)', () {
      final seed = Uint8List.fromList(List<int>.generate(64, (i) => i));

      test('matches the pure-Dart public key for the same 64-byte seed',
          () async {
        final ffiAlgo = MlKem768FfiAlgo.fromLib(lib!);
        final ffiKp = await ffiAlgo.generateKeyPair(seed);
        final pureKp = await MlKem768PureDartAlgo.instance.generateKeyPair(seed);
        try {
          expect(ffiKp.publicKey, equals(pureKp.publicKey));
        } finally {
          ffiAlgo.releaseKeyPair(ffiKp);
        }
      });

      test('encapsulate/decapsulate round-trip with a seeded key pair',
          () async {
        final ffiAlgo = MlKem768FfiAlgo.fromLib(lib!);
        final kp = await ffiAlgo.generateKeyPair(seed);
        try {
          final enc = await ffiAlgo.encapsulate(kp.publicKey);
          final Uint8List recovered =
              await ffiAlgo.decapsulate(kp.secretKey, enc.ciphertext);
          expect(recovered, equals(enc.sharedSecret));
        } finally {
          ffiAlgo.releaseKeyPair(kp);
        }
      });

      test('rejects a seed that is not 64 bytes', () async {
        final ffiAlgo = MlKem768FfiAlgo.fromLib(lib!);
        expect(
          () => ffiAlgo.generateKeyPair(Uint8List(32)),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test('encapsulate throws ArgumentError for a wrong-length public key',
        () async {
      final algo = MlKem768FfiAlgo.fromLib(lib!);
      final Uint8List badPub = Uint8List(MlKem768Sizes.publicKeyBytes - 1);
      expect(() => algo.encapsulate(badPub), throwsA(isA<ArgumentError>()));
    });

    test('decapsulate throws ArgumentError for a wrong-length ciphertext',
        () async {
      final algo = MlKem768FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      try {
        final Uint8List badCt = Uint8List(MlKem768Sizes.ciphertextBytes + 1);
        expect(() => algo.decapsulate(kp.secretKey, badCt),
            throwsA(isA<ArgumentError>()));
      } finally {
        algo.releaseKeyPair(kp);
      }
    });

    test('decapsulate throws ArgumentError for a wrong-length secret-key '
        'handle', () async {
      final algo = MlKem768FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      try {
        final enc = await algo.encapsulate(kp.publicKey);
        final Uint8List shortHandle = Uint8List(7);
        final Uint8List longHandle = Uint8List(9);

        expect(() => algo.decapsulate(shortHandle, enc.ciphertext),
            throwsA(isA<ArgumentError>()));
        expect(() => algo.decapsulate(longHandle, enc.ciphertext),
            throwsA(isA<ArgumentError>()));
      } finally {
        algo.releaseKeyPair(kp);
      }
    });
  });
}
