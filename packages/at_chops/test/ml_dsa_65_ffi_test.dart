@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('ML-DSA-65 FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);
    final bool mlDsaSupported = lib != null && libCryptoSupportsMlDsa65(lib);
    final String? skipReason = lib == null
        ? 'libcrypto not available on this host'
        : !mlDsaSupported
            ? 'libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.3)'
            : null;

    setUpAll(() {
      if (lib != null) {
        // ignore: avoid_print
        print('libcrypto loaded from: ${loadedPath.toString()}');
      }
    });

    test(
      'FFI keygen/sign/verify round-trip',
      () async {
        final algo = MlDsa65FfiAlgo.fromLib(lib!);
        final kp = await algo.generateKeyPair();

        expect(kp.publicKey.length, equals(1952));
        expect(kp.secretKey.length, equals(4032));

        final Uint8List message =
            Uint8List.fromList('Hello ML-DSA-65 FFI'.codeUnits);
        final Uint8List sig = await algo.signBytes(kp.secretKey, message);
        expect(sig.length, equals(3309));

        final bool ok = await algo.verifyBytes(kp.publicKey, message, sig);
        expect(ok, isTrue);
      },
      skip: skipReason,
    );

    test(
      'Interop A: pure-Dart keygen → FFI sign → pure-Dart verify',
      () async {
        final AtMlDsa65KeyPair kp = await AtChopsUtil.generateMlDsa65KeyPair();
        final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
        final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

        final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib!);
        final Uint8List message =
            Uint8List.fromList('cross-backend signing'.codeUnits);
        final Uint8List sig = await ffiAlgo.signBytes(sk, message);

        final bool ok =
            await MlDsa65PureDartAlgo.verifyBytes(message, sig, pub);
        expect(ok, isTrue);
      },
      skip: skipReason,
    );

    test(
      'Interop B: FFI keygen → pure-Dart sign → FFI verify',
      () async {
        final ffiAlgo = MlDsa65FfiAlgo.fromLib(lib!);
        final kp = await ffiAlgo.generateKeyPair();

        final Uint8List message =
            Uint8List.fromList('cross-backend verification'.codeUnits);
        final Uint8List sig =
            await MlDsa65PureDartAlgo.signBytes(message, kp.secretKey);

        final bool ok =
            await ffiAlgo.verifyBytes(kp.publicKey, message, sig);
        expect(ok, isTrue);
      },
      skip: skipReason,
    );

    test(
      'FFI verify returns false for tampered message',
      () async {
        final algo = MlDsa65FfiAlgo.fromLib(lib!);
        final kp = await algo.generateKeyPair();

        final Uint8List message = Uint8List.fromList('original'.codeUnits);
        final Uint8List sig = await algo.signBytes(kp.secretKey, message);

        final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
        final bool ok = await algo.verifyBytes(kp.publicKey, tampered, sig);
        expect(ok, isFalse);
      },
      skip: skipReason,
    );
  });
}
