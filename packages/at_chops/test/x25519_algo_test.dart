import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('X25519 pure-Dart', () {
    final algo = X25519PureDartAlgo.instance;

    test('DH round-trip: Alice and Bob derive the same shared secret',
        () async {
      final aliceRaw = await algo.generateKeyPair();
      final bobRaw = await algo.generateKeyPair();
      final AtX25519KeyPair alice =
          AtX25519KeyPair.fromBytes(aliceRaw.publicKey, aliceRaw.privateKey);
      final AtX25519KeyPair bob =
          AtX25519KeyPair.fromBytes(bobRaw.publicKey, bobRaw.privateKey);

      final Uint8List alicePub = base64Decode(alice.atPublicKey.publicKey);
      final Uint8List alicePriv = base64Decode(alice.atPrivateKey.privateKey);
      final Uint8List bobPub = base64Decode(bob.atPublicKey.publicKey);
      final Uint8List bobPriv = base64Decode(bob.atPrivateKey.privateKey);

      final Uint8List ss1 = await algo.dh(alicePriv, bobPub);
      final Uint8List ss2 = await algo.dh(bobPriv, alicePub);

      expect(ss1, equals(ss2));
      expect(ss1.length, equals(32));
    });

    test('Generated key pair has 32-byte public and private keys', () async {
      final raw = await algo.generateKeyPair();
      final AtX25519KeyPair kp =
          AtX25519KeyPair.fromBytes(raw.publicKey, raw.privateKey);
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(32));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(32));
    });
  });

  group('X25519 FFI', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();

    test(
      'DH round-trip via OpenSSL FFI',
      () async {
        final algo = X25519FfiAlgo.fromLib(lib!);
        // Generate keys via FFI directly to keep raw bytes consistent.
        final aliceKp = await X25519FfiAlgo.fromLib(lib).generateKeyPair();
        final bobKp = await X25519FfiAlgo.fromLib(lib).generateKeyPair();

        final Uint8List ss1 =
            await algo.dh(aliceKp.privateKey, bobKp.publicKey);
        final Uint8List ss2 =
            await algo.dh(bobKp.privateKey, aliceKp.publicKey);

        expect(ss1, equals(ss2));
        expect(ss1.length, equals(32));
      },
      skip: lib == null ? 'libcrypto not available on this host' : null,
    );

    test(
      'Pure-Dart and FFI interop: same keys yield the same shared secret',
      () async {
        final pureAlgo = X25519PureDartAlgo.instance;
        final ffiAlgo = X25519FfiAlgo.fromLib(lib!);

        final aliceRaw = await pureAlgo.generateKeyPair();
        final bobRaw = await pureAlgo.generateKeyPair();

        final Uint8List ssPure =
            await pureAlgo.dh(aliceRaw.privateKey, bobRaw.publicKey);
        final Uint8List ssFfi =
            await ffiAlgo.dh(aliceRaw.privateKey, bobRaw.publicKey);

        expect(ssPure, equals(ssFfi));
      },
      skip: lib == null ? 'libcrypto not available on this host' : null,
    );
  });
}
