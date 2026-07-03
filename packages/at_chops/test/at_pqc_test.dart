import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:test/test.dart';

void main() {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  final bool xWingFfi = lib != null && libCryptoSupportsMlKem768(lib);
  final bool mlDsaFfi = lib != null && libCryptoSupportsMlDsa65(lib);

  group('AtPqc — host-agnostic', () {
    test('AtPqc.xWing is FFI when supported, else pure', () {
      if (xWingFfi) {
        expect(AtPqc.xWing, isA<XWingFfiAlgo>());
      } else {
        expect(AtPqc.xWing, isA<XWingPureDartAlgo>());
      }
    });

    test('AtPqc.mlDsa65 is FFI when supported, else pure', () {
      if (mlDsaFfi) {
        expect(AtPqc.mlDsa65, isA<MlDsa65FfiAlgo>());
      } else {
        expect(AtPqc.mlDsa65, isA<MlDsa65PureDartAlgo>());
      }
    });

    test('xWing encapsulate/decapsulate round-trip', () async {
      final XWingKeyPair kp = await XWingKeyPair.generate();

      final enc = await AtPqc.xWing.encapsulate(kp.publicKeyBytes);
      expect(enc.ciphertext.length, 1120);
      expect(enc.sharedSecret.length, 32);

      final ss = await AtPqc.xWing.decapsulate(kp.privateKeyBytes, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });

    test('mlDsa65 signBytes/verifyBytes round-trip', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();

      final Uint8List msg = Uint8List.fromList('hello pqc'.codeUnits);
      final Uint8List sig = await AtPqc.mlDsa65.signBytes(msg, kp.privateKeyBytes);
      final bool ok = await AtPqc.mlDsa65.verifyBytes(msg, sig, kp.publicKeyBytes);
      expect(ok, isTrue);
    });

    test('AtPqc.xWing.generateKeyPair() round-trips directly, with no wrapper',
        () async {
      final kp = await AtPqc.xWing.generateKeyPair();
      expect(kp.publicKey.length, 1216);
      expect(kp.secretKey.length, 32);

      final enc = await AtPqc.xWing.encapsulate(kp.publicKey);
      final ss = await AtPqc.xWing.decapsulate(kp.secretKey, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });

    test('AtPqc.mlDsa65.generateKeyPair() round-trips directly, with no wrapper',
        () async {
      final kp = await AtPqc.mlDsa65.generateKeyPair();
      expect(kp.publicKey.length, 1952);
      expect(kp.secretKey.length, 4032);

      final Uint8List msg = Uint8List.fromList('direct facade keygen'.codeUnits);
      final Uint8List sig = await AtPqc.mlDsa65.signBytes(msg, kp.secretKey);
      expect(await AtPqc.mlDsa65.verifyBytes(msg, sig, kp.publicKey), isTrue);
    });

    test(
        'XWingKeyPair.generate() (pure-Dart) is interoperable with AtPqc.xWing '
        'regardless of which backend AtPqc selects', () async {
      // XWingKeyPair.generate() is pure-Dart-only by design — it must stay
      // out of the dart:ffi import graph so at_chops.dart (the web-safe
      // barrel) keeps compiling for web/wasm. It does NOT delegate to
      // AtPqc.xWing. This only checks the two backends stay wire-compatible.
      final XWingKeyPair kp = await XWingKeyPair.generate();
      final enc = await AtPqc.xWing.encapsulate(kp.publicKeyBytes);
      final ss = await AtPqc.xWing.decapsulate(kp.privateKeyBytes, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });

    test(
        'MlDsa65KeyPair.generate() (pure-Dart) is interoperable with '
        'AtPqc.mlDsa65 regardless of which backend AtPqc selects', () async {
      // Same rationale as XWingKeyPair above — MlDsa65KeyPair.generate()
      // is pure-Dart-only and does not delegate to AtPqc.mlDsa65.
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List msg = Uint8List.fromList('cross-backend key reuse'.codeUnits);
      final Uint8List sig = await AtPqc.mlDsa65.signBytes(msg, kp.privateKeyBytes);
      expect(await AtPqc.mlDsa65.verifyBytes(msg, sig, kp.publicKeyBytes), isTrue);
    });
  });

  // These tests require libcrypto (OpenSSL >= 3.5) at runtime.
  // They are tagged 'ffi' and intentionally FAIL (not skip) when the library
  // is missing or too old — CI must provide OpenSSL before running --tags ffi.
  group('AtPqc — FFI cross-backend interop', () {
    test('X-Wing: FFI encapsulate, pure-Dart decapsulate', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!xWingFfi) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final XWingKeyPair kp = await XWingKeyPair.generate();
      final ffiAlgo = XWingFfiAlgo.fromLib(lib);
      final enc = await ffiAlgo.encapsulate(kp.publicKeyBytes);
      final ss = await XWingPureDartAlgo.instance.decapsulate(kp.privateKeyBytes, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    }, tags: ['ffi']);

    test('X-Wing: pure-Dart encapsulate, FFI decapsulate', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!xWingFfi) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final XWingKeyPair kp = await XWingKeyPair.generate();
      final enc = await XWingPureDartAlgo.instance.encapsulate(kp.publicKeyBytes);
      final ffiAlgo = XWingFfiAlgo.fromLib(lib);
      final ss = await ffiAlgo.decapsulate(kp.privateKeyBytes, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    }, tags: ['ffi']);

    test('ML-DSA-65: FFI sign, pure-Dart verify', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!mlDsaFfi) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.3)');
      }

      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List msg = Uint8List.fromList('cross-backend sign'.codeUnits);
      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final Uint8List sig = await ffiAlgo.signBytes(msg, kp.privateKeyBytes);
      final bool ok =
          await MlDsa65PureDartAlgo().verifyBytes(msg, sig, kp.publicKeyBytes);
      expect(ok, isTrue);
    }, tags: ['ffi']);

    test('ML-DSA-65: pure-Dart sign, FFI verify', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!mlDsaFfi) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.3)');
      }

      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List msg = Uint8List.fromList('cross-backend verify'.codeUnits);
      final Uint8List sig =
          await MlDsa65PureDartAlgo().signBytes(msg, kp.privateKeyBytes);
      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final bool ok = await ffiAlgo.verifyBytes(msg, sig, kp.publicKeyBytes);
      expect(ok, isTrue);
    }, tags: ['ffi']);
  });
}
