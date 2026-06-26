import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:test/test.dart';

void main() {
  final StringBuffer loadedPath = StringBuffer();
  final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);
  final bool xWingFfi = lib != null && libCryptoSupportsMlKem768(lib);
  final bool mlDsaFfi = lib != null && libCryptoSupportsMlDsa65(lib);

  setUpAll(() {
    if (lib != null) {
      // ignore: avoid_print
      print('libcrypto loaded from: ${loadedPath.toString()}');
    }
  });

  group('PqcFfi — host-agnostic', () {
    test('PqcFfi.xWing is FFI when supported, else pure', () {
      if (xWingFfi) {
        expect(PqcFfi.xWing, isA<XWingFfiAlgo>());
      } else {
        expect(PqcFfi.xWing, isA<XWingPureDartAlgo>());
      }
    });

    test('PqcFfi.mlDsa65 is FFI when supported, else pure', () {
      if (mlDsaFfi) {
        expect(PqcFfi.mlDsa65, isA<MlDsa65FfiAlgo>());
      } else {
        expect(PqcFfi.mlDsa65, isA<MlDsa65PureDartAlgo>());
      }
    });

    test('xWing encapsulate/decapsulate round-trip', () async {
      final XWingKeyPair kp = await XWingKeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final enc = await PqcFfi.xWing.encapsulate(pub);
      expect(enc.ciphertext.length, 1120);
      expect(enc.sharedSecret.length, 32);

      final ss = await PqcFfi.xWing.decapsulate(sk, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    });

    test('mlDsa65 signBytes/verifyBytes round-trip', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List msg = Uint8List.fromList('hello pqc'.codeUnits);
      final Uint8List sig = await PqcFfi.mlDsa65.signBytes(msg, sk);
      final bool ok = await PqcFfi.mlDsa65.verifyBytes(msg, sig, pub);
      expect(ok, isTrue);
    });
  });

  group('PqcFfi — FFI cross-backend interop', () {
    test('X-Wing: FFI encapsulate, pure-Dart decapsulate', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!xWingFfi) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final XWingKeyPair kp = await XWingKeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final ffiAlgo = XWingFfiAlgo.fromLib(lib);
      final enc = await ffiAlgo.encapsulate(pub);
      final ss =
          await XWingPureDartAlgo.instance.decapsulate(sk, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    }, tags: ['ffi']);

    test('X-Wing: pure-Dart encapsulate, FFI decapsulate', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!xWingFfi) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }

      final XWingKeyPair kp = await XWingKeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final enc = await XWingPureDartAlgo.instance.encapsulate(pub);
      final ffiAlgo = XWingFfiAlgo.fromLib(lib);
      final ss = await ffiAlgo.decapsulate(sk, enc.ciphertext);
      expect(ss, enc.sharedSecret);
    }, tags: ['ffi']);

    test('ML-DSA-65: FFI sign, pure-Dart verify', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!mlDsaFfi) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.3)');
      }

      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List msg =
          Uint8List.fromList('cross-backend sign'.codeUnits);
      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final Uint8List sig = await ffiAlgo.signBytes(msg, sk);
      final bool ok = await MlDsa65PureDartAlgo().verifyBytes(msg, sig, pub);
      expect(ok, isTrue);
    }, tags: ['ffi']);

    test('ML-DSA-65: pure-Dart sign, FFI verify', () async {
      if (lib == null) fail('libcrypto not available on this host');
      if (!mlDsaFfi) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.3)');
      }

      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List msg =
          Uint8List.fromList('cross-backend verify'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo().signBytes(msg, sk);
      final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib);
      final bool ok = await ffiAlgo.verifyBytes(msg, sig, pub);
      expect(ok, isTrue);
    }, tags: ['ffi']);
  });
}
