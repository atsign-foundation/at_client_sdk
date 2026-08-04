@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/src/algorithm/spec/ml_dsa_65_spec.dart';
import 'package:at_commons/at_commons.dart' show AtSigningException;
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
      expect(algo.name, equals('ml-dsa-65'),
          reason: 'must match MlDsa65PureDartAlgo.name — a downstream '
              'protocol sees one identifier regardless of backend');
      expect(algo.signingAlgoType, equals(SigningAlgoType.mldsa65),
          reason: 'must match MlDsa65PureDartAlgo.signingAlgoType — both '
              'backends report the same pkam:/envelope wire identifier');
      final kp = await algo.generateKeyPair();

      expect(kp.publicKey.length, equals(1952));
      expect(kp.secretKey.length, equals(4032));

      final Uint8List message =
          Uint8List.fromList('Hello ML-DSA-65 FFI'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: kp.secretKey);
      expect(sig.length, equals(3309));

      final bool ok = await algo.verifyBytes(message, signature: sig, publicKey: kp.publicKey);
      expect(ok, isTrue);
    });

    test('Interop A: pure-Dart keygen → FFI sign → pure-Dart verify', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final Uint8List message =
          Uint8List.fromList('cross-backend signing'.codeUnits);
      final Uint8List sig = await ffiAlgo.signBytes(message, secretKey: sk);

      final bool ok =
          await MlDsa65PureDartAlgo().verifyBytes(message, signature: sig, publicKey: pub);
      expect(ok, isTrue);
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
      final Uint8List sig =
          await MlDsa65PureDartAlgo().signBytes(message, secretKey: kp.secretKey);

      final bool ok = await ffiAlgo.verifyBytes(message, signature: sig, publicKey: kp.publicKey);
      expect(ok, isTrue);
    });

    test('FFI verify returns false for tampered message', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      final kp = await algo.generateKeyPair();

      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      final bool ok = await algo.verifyBytes(tampered, signature: sig, publicKey: kp.publicKey);
      expect(ok, isFalse);
    });

    test('signBytes throws AtSigningException for a short secret key', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List shortSk = Uint8List(MlDsa65Sizes.secretKeyBytes - 1);

      expect(() => algo.signBytes(message, secretKey: shortSk),
          throwsA(isA<AtSigningException>()));
    });

    test(
        'signBytes throws AtSigningException for an over-long secret key '
        '(same contract as the pure-Dart backend)', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List longSk = Uint8List(MlDsa65Sizes.secretKeyBytes + 1);

      expect(() => algo.signBytes(message, secretKey: longSk),
          throwsA(isA<AtSigningException>()));
    });

    test('verifyBytes returns false (never throws) for a wrong-length public key',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List badPub = Uint8List(MlDsa65Sizes.publicKeyBytes - 1);
      final bool ok =
          await algo.verifyBytes(message, signature: sig, publicKey: badPub);

      expect(ok, isFalse);
    });

    test('verifyBytes returns false (never throws) for a wrong-length signature',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }
      if (!mlDsaSupported) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }

      final algo = MlDsa65FfiAlgo.fromLib(lib);
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List badSig = Uint8List(MlDsa65Sizes.signatureBytes + 1);
      final bool ok = await algo.verifyBytes(message,
          signature: badSig, publicKey: kp.publicKey);

      expect(ok, isFalse);
    });
  });
}
