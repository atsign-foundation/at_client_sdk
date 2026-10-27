@Tags(['ffi'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
// `show`: at_commons exports its own StringBuffer, which would shadow
// dart:core's and break the loadedPath argument below.
import 'package:at_commons/at_commons.dart'
    show AtSigningException, AtSigningVerificationException;
import 'package:test/test.dart';

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

    test('FFI keygen/sign/verify round-trip', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      expect(algo.name, equals('mldsa65'),
          reason: 'must match MlDsa65PureDartAlgo.name — a downstream '
              'protocol sees one identifier regardless of backend');
      final kp = await algo.generateKeyPair();

      expect(kp.publicKey.length, equals(1952));
      expect(kp.secretKey.length, equals(4032));

      final Uint8List message =
          Uint8List.fromList('Hello ML-DSA-65 FFI'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);
      expect(sig.length, equals(3309));

      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: kp.publicKey),
          completes);
    });

    test('Interop A: pure-Dart keygen → FFI sign → pure-Dart verify', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final kp = await MlDsa65PureDartAlgo().generateKeyPair();

      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final Uint8List message =
          Uint8List.fromList('cross-backend signing'.codeUnits);
      final Uint8List sig =
          await ffiAlgo.signBytes(message, secretKey: kp.secretKey);

      await expectLater(
          MlDsa65PureDartAlgo()
              .verifyBytes(message, signature: sig, publicKey: kp.publicKey),
          completes);
    });

    test('Interop B: FFI keygen → pure-Dart sign → FFI verify', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final kp = await ffiAlgo.generateKeyPair();

      final Uint8List message =
          Uint8List.fromList('cross-backend verification'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo()
          .signBytes(message, secretKey: kp.secretKey);

      await expectLater(
          ffiAlgo.verifyBytes(message, signature: sig, publicKey: kp.publicKey),
          completes);
    });

    test('FFI verify throws for tampered message', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      final kp = await algo.generateKeyPair();

      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      await expectLater(
          algo.verifyBytes(tampered, signature: sig, publicKey: kp.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
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

    test('verifyBytes throws for a wrong-length public key', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List badPub = Uint8List(MlDsa65Sizes.publicKeyBytes - 1);
      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: badPub),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('verifyBytes throws for a wrong-length signature', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List badSig = Uint8List(MlDsa65Sizes.signatureBytes + 1);
      await expectLater(
          algo.verifyBytes(message, signature: badSig, publicKey: kp.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    // The two wrong-length cases above never reach OpenSSL — the length gate
    // rejects them first. These two do, and pin the boundary that lets
    // verifyBytes carry no catch-all: attacker-controlled bytes of the right
    // length come back as a verification failure, while a StateError means
    // the backend itself failed.
    test('verifyBytes throws for a right-length garbage public key', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List garbagePub = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.publicKeyBytes, (int i) => (i * 7 + 13) % 256));

      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: garbagePub),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('verifyBytes throws for a right-length garbage signature', () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List garbageSig = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.signatureBytes, (int i) => (i * 11 + 29) % 256));

      await expectLater(
          algo.verifyBytes(message,
              signature: garbageSig, publicKey: kp.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test(
        'fromLib throws AtSigningException when the injected probe reports '
        'no ML-DSA-65 support — runs on every host, no libcrypto required', () {
      final DynamicLibrary probedLib = lib ?? DynamicLibrary.process();

      expect(
          () =>
              MlDsa65FfiAlgo.fromLib(probedLib, supportsMlDsa65: (_) => false),
          throwsA(isA<AtSigningException>()));
    });
  });
}
