import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 pure-Dart', () {
    final algo = MlKem768PureDartAlgo.instance;

    test('encapsulate/decapsulate round-trip yields matching shared secrets',
        () async {
      final raw = await algo.generateKeyPair();
      final AtMlKem768KeyPair kp =
          AtMlKem768KeyPair.fromBytes(raw.publicKey, raw.secretKey);
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

      final enc = await algo.encapsulate(pub);
      final Uint8List recovered = await algo.decapsulate(priv, enc.ciphertext);

      expect(recovered, equals(enc.sharedSecret));
      expect(enc.sharedSecret.length, equals(32));
    });

    test('Generated key pair has FIPS 203 key sizes', () async {
      final raw = await algo.generateKeyPair();
      final AtMlKem768KeyPair kp =
          AtMlKem768KeyPair.fromBytes(raw.publicKey, raw.secretKey);
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(1184));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(2400));
    });

    test('Decapsulating tampered ciphertext does not throw and (per FIPS 203)'
        ' returns an implicit-rejection secret different from the real one',
        () async {
      final raw = await algo.generateKeyPair();
      final AtMlKem768KeyPair kp =
          AtMlKem768KeyPair.fromBytes(raw.publicKey, raw.secretKey);
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

      final enc = await algo.encapsulate(pub);

      final Uint8List tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;

      final Uint8List bad = await algo.decapsulate(priv, tampered);
      expect(bad, isNot(equals(enc.sharedSecret)));
      expect(bad.length, equals(32));
    });
  });

  group('ML-KEM-768 FFI', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();

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
      skip: lib == null ? 'libcrypto not available on this host' : null,
    );

    test(
      'FFI sender can encapsulate against a pure-Dart-generated public key',
      () async {
        final raw = await MlKem768PureDartAlgo.instance.generateKeyPair();
        final AtMlKem768KeyPair kp =
            AtMlKem768KeyPair.fromBytes(raw.publicKey, raw.secretKey);
        final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
        final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

        final ffiAlgo = MlKem768FfiAlgo.fromLib(lib!);
        final enc = await ffiAlgo.encapsulate(pub);

        // Recipient must use pure-Dart impl — FFI handles are non-serializable.
        final Uint8List recovered = await MlKem768PureDartAlgo.instance
            .decapsulate(priv, enc.ciphertext);
        expect(recovered, equals(enc.sharedSecret));
      },
      skip: lib == null ? 'libcrypto not available on this host' : null,
    );
  });
}
