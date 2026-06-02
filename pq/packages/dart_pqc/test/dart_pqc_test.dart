import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_pqc/dart_pqc.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 (pure Dart)', () {
    final KemAlgorithm kem = MlKem768PureDart.instance;

    test('name', () {
      expect(kem.name, equals('ML-KEM-768'));
    });

    test('round-trip: shared secrets match', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);

      expect(enc.sharedSecret, equals(ss2));
    });

    test('shared secret is 32 bytes', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);

      expect(enc.sharedSecret.length, equals(32));
    });

    test('different key pairs produce different shared secrets', () async {
      final PqcKeyPair kp1 = await kem.generateKeyPair();
      final PqcKeyPair kp2 = await kem.generateKeyPair();

      final EncapsulationResult enc1 = await kem.encapsulate(kp1.publicKey);
      final EncapsulationResult enc2 = await kem.encapsulate(kp2.publicKey);

      expect(enc1.sharedSecret, isNot(equals(enc2.sharedSecret)));
    });

    test('deterministic key gen with 64-byte seed (d||z)', () async {
      final Uint8List seed = Uint8List(64)..fillRange(0, 64, 0x42);
      final PqcKeyPair kp1 = await kem.generateKeyPair(seed);
      final PqcKeyPair kp2 = await kem.generateKeyPair(seed);

      expect(kp1.publicKey, equals(kp2.publicKey));
      expect(kp1.secretKey, equals(kp2.secretKey));
    });
  });

  group('X25519 (pure Dart)', () {
    final KemAlgorithm kem = X25519PureDart.instance;

    test('name', () {
      expect(kem.name, equals('X25519'));
    });

    test('round-trip: shared secrets match', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);

      expect(enc.sharedSecret, equals(ss2));
    });

    test('shared secret is 32 bytes', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);

      expect(enc.sharedSecret.length, equals(32));
    });

    test('different key pairs produce different shared secrets', () async {
      final PqcKeyPair kp1 = await kem.generateKeyPair();
      final PqcKeyPair kp2 = await kem.generateKeyPair();

      final EncapsulationResult enc1 = await kem.encapsulate(kp1.publicKey);
      final EncapsulationResult enc2 = await kem.encapsulate(kp2.publicKey);

      expect(enc1.sharedSecret, isNot(equals(enc2.sharedSecret)));
    });
  });

  group('ML-KEM-768 (FFI)', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final MlKem768Ffi kem;

    setUpAll(() {
      if (ffiAvailable) kem = MlKem768Ffi.fromLib(lib!);
    });

    test('name', () {
      if (!ffiAvailable) return;
      expect(kem.name, equals('ML-KEM-768'));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('round-trip: shared secrets match', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
      kem.releaseKeyPair(kp);
      expect(enc.sharedSecret, equals(ss2));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('shared secret is 32 bytes', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      kem.releaseKeyPair(kp);
      expect(enc.sharedSecret.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('different key pairs produce different shared secrets', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp1 = await kem.generateKeyPair();
      final PqcKeyPair kp2 = await kem.generateKeyPair();
      final EncapsulationResult enc1 = await kem.encapsulate(kp1.publicKey);
      final EncapsulationResult enc2 = await kem.encapsulate(kp2.publicKey);
      kem.releaseKeyPair(kp1);
      kem.releaseKeyPair(kp2);
      expect(enc1.sharedSecret, isNot(equals(enc2.sharedSecret)));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('public key is 1184 bytes', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp = await kem.generateKeyPair();
      kem.releaseKeyPair(kp);
      expect(kp.publicKey.length, equals(1184));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  group('X25519 (FFI)', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final X25519Ffi kem;

    setUpAll(() {
      if (ffiAvailable) kem = X25519Ffi.fromLib(lib!);
    });

    test('name', () {
      if (!ffiAvailable) return;
      expect(kem.name, equals('X25519'));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('round-trip: shared secrets match', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('shared secret is 32 bytes', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      expect(enc.sharedSecret.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('different key pairs produce different shared secrets', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp1 = await kem.generateKeyPair();
      final PqcKeyPair kp2 = await kem.generateKeyPair();
      final EncapsulationResult enc1 = await kem.encapsulate(kp1.publicKey);
      final EncapsulationResult enc2 = await kem.encapsulate(kp2.publicKey);
      expect(enc1.sharedSecret, isNot(equals(enc2.sharedSecret)));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('public and secret keys are 32 bytes', () async {
      if (!ffiAvailable) return;
      final PqcKeyPair kp = await kem.generateKeyPair();
      expect(kp.publicKey.length, equals(32));
      expect(kp.secretKey.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  group('resolver', () {
    test('resolveMlKem768 returns a KemAlgorithm', () {
      final KemAlgorithm kem = resolveMlKem768();
      expect(kem, isA<KemAlgorithm>());
      expect(kem.name, equals('ML-KEM-768'));
    });

    test('resolveX25519 returns a KemAlgorithm', () {
      final KemAlgorithm kem = resolveX25519();
      expect(kem, isA<KemAlgorithm>());
      expect(kem.name, equals('X25519'));
    });

    test('resolved ML-KEM-768 round-trip works', () async {
      final KemAlgorithm kem = resolveMlKem768();
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    });

    test('resolved X25519 round-trip works', () async {
      final KemAlgorithm kem = resolveX25519();
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    });
  });
}
