@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 FFI', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool mlKemSupported =
        lib != null && libCryptoSupportsMlKem768(lib);
    final String? skipReason = lib == null
        ? 'libcrypto not available on this host'
        : !mlKemSupported
            ? 'libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.3)'
            : null;

    test(
      'encapsulate/decapsulate round-trip within the FFI instance',
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
      },
      skip: skipReason,
    );

    test(
      'FFI sender can encapsulate against a pure-Dart-generated public key',
      () async {
        final AtMlKem768KeyPair kp =
            await AtChopsUtil.generateMlKem768KeyPair();
        final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
        final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

        final ffiAlgo = MlKem768FfiAlgo.fromLib(lib!);
        final enc = await ffiAlgo.encapsulate(pub);

        // Recipient must use pure-Dart impl — FFI handles are non-serializable.
        final Uint8List recovered = await MlKem768PureDartAlgo.instance
            .decapsulate(priv, enc.ciphertext);
        expect(recovered, equals(enc.sharedSecret));
      },
      skip: skipReason,
    );
  });
}
