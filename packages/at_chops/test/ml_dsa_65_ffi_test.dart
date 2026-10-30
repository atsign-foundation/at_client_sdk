@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:test/test.dart';

import 'ml_dsa_65_acvp_vectors.dart';

void main() {
  group('ML-DSA-65 FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);
    final bool mlDsaSupported = lib != null && libCryptoSupportsMlDsa65(lib);

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
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }
    });

    test('FFI keygen/sign/verify round-trip', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();

      expect(kp.publicKey.length, equals(1952));
      expect(kp.secretKey.length, equals(4032));

      final Uint8List message =
          Uint8List.fromList('Hello ML-DSA-65 FFI'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);
      expect(sig.length, equals(3309));

      final bool ok = await algo.verifyBytes(message,
          signature: sig, publicKey: kp.publicKey);
      expect(ok, isTrue);
    });

    test('Interop A: pure-Dart keygen → FFI sign → pure-Dart verify', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib!);
      final Uint8List message =
          Uint8List.fromList('cross-backend signing'.codeUnits);
      final Uint8List sig = await ffiAlgo.signBytes(message, secretKey: sk);

      final bool ok = await MlDsa65PureDartAlgo()
          .verifyBytes(message, signature: sig, publicKey: pub);
      expect(ok, isTrue);
    });

    test('Interop B: FFI keygen → pure-Dart sign → FFI verify', () async {
      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await ffiAlgo.generateKeyPair();

      final Uint8List message =
          Uint8List.fromList('cross-backend verification'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo()
          .signBytes(message, secretKey: kp.secretKey);

      final bool ok = await ffiAlgo.verifyBytes(message,
          signature: sig, publicKey: kp.publicKey);
      expect(ok, isTrue);
    });

    test('FFI verify returns false for tampered message', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();

      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      final bool ok = await algo.verifyBytes(tampered,
          signature: sig, publicKey: kp.publicKey);
      expect(ok, isFalse);
    });

    test('signBytes throws ArgumentError for a short secret key', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List shortSk = Uint8List(MlDsa65Sizes.secretKeyBytes - 1);

      expect(() => algo.signBytes(message, secretKey: shortSk),
          throwsA(isA<ArgumentError>()));
    });

    test(
        'signBytes throws ArgumentError for an over-long secret key '
        '(same contract as the pure-Dart backend)', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List longSk = Uint8List(MlDsa65Sizes.secretKeyBytes + 1);

      expect(() => algo.signBytes(message, secretKey: longSk),
          throwsA(isA<ArgumentError>()));
    });

    test('verifyBytes returns false for a wrong-length public key', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List badPub = Uint8List(MlDsa65Sizes.publicKeyBytes - 1);
      final bool ok =
          await algo.verifyBytes(message, signature: sig, publicKey: badPub);

      expect(ok, isFalse);
    });

    test('verifyBytes returns false for a wrong-length signature', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List badSig = Uint8List(MlDsa65Sizes.signatureBytes + 1);
      final bool ok = await algo.verifyBytes(message,
          signature: badSig, publicKey: kp.publicKey);

      expect(ok, isFalse);
    });

    // The two wrong-length cases above never reach OpenSSL — the length gate
    // rejects them first. These two do, and pin the boundary that lets
    // verifyBytes carry no catch-all: attacker-controlled bytes of the right
    // length must come back as `false`, while a StateError means the backend
    // itself failed.
    test('verifyBytes returns false for a right-length garbage public key',
        () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List garbagePub = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.publicKeyBytes, (int i) => (i * 7 + 13) % 256));
      final bool ok = await algo.verifyBytes(message,
          signature: sig, publicKey: garbagePub);

      expect(ok, isFalse);
    });

    test('verifyBytes returns false for a right-length garbage signature',
        () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List garbageSig = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.signatureBytes, (int i) => (i * 11 + 29) % 256));
      final bool ok = await algo.verifyBytes(message,
          signature: garbageSig, publicKey: kp.publicKey);

      expect(ok, isFalse);
    });

    group('keyPairFromSeed', () {
      for (final v in mlDsa65KeyGenVectors()) {
        test('ACVP tcId ${v.tcId}: the seed derives the published keypair',
            () async {
          final kp = await MlDsa65FfiAlgo.fromLib(lib!).keyPairFromSeed(v.seed);
          expect(kp.publicKey, v.pk);
          expect(kp.secretKey, v.sk);
        });
      }

      test('derives the same keypair as pure-Dart for random seeds', () async {
        final ffi = MlDsa65FfiAlgo.fromLib(lib!);
        final pure = MlDsa65PureDartAlgo();
        final Random random = Random.secure();
        for (var i = 0; i < 16; i++) {
          final Uint8List seed = Uint8List.fromList(List<int>.generate(
              MlDsa65Sizes.seedBytes, (_) => random.nextInt(256)));
          final a = await ffi.keyPairFromSeed(seed);
          final b = await pure.keyPairFromSeed(seed);
          expect(a.publicKey, b.publicKey, reason: 'seed $seed');
          expect(a.secretKey, b.secretKey, reason: 'seed $seed');
        }
      });

      test('a seeded keypair signs with FFI and verifies with pure-Dart',
          () async {
        final ffi = MlDsa65FfiAlgo.fromLib(lib!);
        final kp = await ffi.keyPairFromSeed(
            Uint8List.fromList(List<int>.filled(MlDsa65Sizes.seedBytes, 9)));
        final Uint8List message = Uint8List.fromList('seeded ffi'.codeUnits);
        final Uint8List sig =
            await ffi.signBytes(message, secretKey: kp.secretKey);
        expect(
            await MlDsa65PureDartAlgo()
                .verifyBytes(message, signature: sig, publicKey: kp.publicKey),
            isTrue);
      });

      for (final int length in [0, 31, 33, 64]) {
        test('a $length-byte seed throws ArgumentError', () {
          expect(
              () => MlDsa65FfiAlgo.fromLib(lib!)
                  .keyPairFromSeed(Uint8List(length)),
              throwsA(isA<ArgumentError>()));
        });
      }
    });
  });
}
