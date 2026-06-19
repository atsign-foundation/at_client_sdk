import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_pqc/dart_pqc.dart';
import 'package:test/test.dart';

void main() {
  // ── ML-KEM-768 ─────────────────────────────────────────────────────────────

  group('ML-KEM-768 (pure Dart)', () {
    final MlKem768Algorithm kem = MlKem768PureDart.instance;

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

  group('ML-KEM-768 (FFI)', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final MlKem768Ffi kem;

    setUpAll(() {
      if (ffiAvailable) kem = MlKem768Ffi.fromLib(lib!);
    });

    test('round-trip: shared secrets match', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
      kem.releaseKeyPair(kp);
      expect(enc.sharedSecret, equals(ss2));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('shared secret is 32 bytes', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      kem.releaseKeyPair(kp);
      expect(enc.sharedSecret.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('public key is 1184 bytes', () async {
      final PqcKeyPair kp = await kem.generateKeyPair();
      kem.releaseKeyPair(kp);
      expect(kp.publicKey.length, equals(1184));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  // ── X25519 ─────────────────────────────────────────────────────────────────

  group('X25519 (pure Dart)', () {
    final X25519PureDart x25519 = X25519PureDart.instance;

    test('round-trip: shared secrets match', () async {
      final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
          await x25519.generateKeyPair();
      final (publicKey: Uint8List bobPk, privateKey: Uint8List bobSk) =
          await x25519.generateKeyPair();

      final Uint8List ss1 = await x25519.dh(aliceSk, bobPk);
      final Uint8List ss2 = await x25519.dh(bobSk, alicePk);
      expect(ss1, equals(ss2));
    });

    test('shared secret is 32 bytes', () async {
      final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
          await x25519.generateKeyPair();
      final (publicKey: _, privateKey: Uint8List bobSk) =
          await x25519.generateKeyPair();
      final Uint8List ss = await x25519.dh(bobSk, alicePk);
      expect(ss.length, equals(32));
    });

    test('key pair sizes are 32 bytes', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await x25519.generateKeyPair();
      expect(pk.length, equals(32));
      expect(sk.length, equals(32));
    });
  });

  group('X25519 (FFI)', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final X25519Ffi x25519;

    setUpAll(() {
      if (ffiAvailable) x25519 = X25519Ffi.fromLib(lib!);
    });

    test('round-trip: shared secrets match', () async {
      final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
          await x25519.generateKeyPair();
      final (publicKey: Uint8List bobPk, privateKey: Uint8List bobSk) =
          await x25519.generateKeyPair();

      final Uint8List ss1 = await x25519.dh(aliceSk, bobPk);
      final Uint8List ss2 = await x25519.dh(bobSk, alicePk);
      expect(ss1, equals(ss2));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('shared secret is 32 bytes', () async {
      final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
          await x25519.generateKeyPair();
      final (publicKey: _, privateKey: Uint8List bobSk) =
          await x25519.generateKeyPair();
      final Uint8List ss = await x25519.dh(bobSk, alicePk);
      expect(ss.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('key pair sizes are 32 bytes', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await x25519.generateKeyPair();
      expect(pk.length, equals(32));
      expect(sk.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  // ── Ed25519 ────────────────────────────────────────────────────────────────

  group('Ed25519 (pure Dart)', () {
    final Ed25519PureDart ed25519 = Ed25519PureDart.instance;

    test('sign and verify succeeds', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('hello dart_pqc'.codeUnits);
      final Uint8List sig = await ed25519.sign(sk, msg);
      expect(await ed25519.verify(pk, msg, sig), isTrue);
    });

    test('tampered message fails verification', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('hello'.codeUnits);
      final Uint8List sig = await ed25519.sign(sk, msg);
      final Uint8List tampered = Uint8List.fromList('HELLO'.codeUnits);
      expect(await ed25519.verify(pk, tampered, sig), isFalse);
    });

    test('signature is 64 bytes', () async {
      final (publicKey: _, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List sig =
          await ed25519.sign(sk, Uint8List.fromList([1, 2, 3]));
      expect(sig.length, equals(64));
    });

    test('key pair sizes are 32 bytes', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      expect(pk.length, equals(32));
      expect(sk.length, equals(32));
    });
  });

  group('Ed25519 (FFI)', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final Ed25519Ffi ed25519;

    setUpAll(() {
      if (ffiAvailable) ed25519 = Ed25519Ffi.fromLib(lib!);
    });

    test('sign and verify succeeds', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('hello dart_pqc'.codeUnits);
      final Uint8List sig = await ed25519.sign(sk, msg);
      expect(await ed25519.verify(pk, msg, sig), isTrue);
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('tampered message fails verification', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('hello'.codeUnits);
      final Uint8List sig = await ed25519.sign(sk, msg);
      final Uint8List tampered = Uint8List.fromList('HELLO'.codeUnits);
      expect(await ed25519.verify(pk, tampered, sig), isFalse);
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('signature is 64 bytes', () async {
      final (publicKey: _, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List sig =
          await ed25519.sign(sk, Uint8List.fromList([1, 2, 3]));
      expect(sig.length, equals(64));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('key pair sizes are 32 bytes', () async {
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      expect(pk.length, equals(32));
      expect(sk.length, equals(32));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  // ── X-Wing (pure Dart) ────────────────────────────────────────────────────

  group('X-Wing (pure Dart)', () {
    final XWingPureDart xwing = XWingPureDart.instance;

    test('round-trip: shared secrets match', () async {
      final PqcKeyPair kp = await xwing.generateKeyPair();
      final EncapsulationResult enc = await xwing.encaps(kp.publicKey);
      final Uint8List ss2 = await xwing.decaps(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    });

    test('shared secret is 32 bytes', () async {
      final PqcKeyPair kp = await xwing.generateKeyPair();
      final EncapsulationResult enc = await xwing.encaps(kp.publicKey);
      expect(enc.sharedSecret.length, equals(32));
    });

    test('pk is 1216 bytes, sk is 2464 bytes', () async {
      final PqcKeyPair kp = await xwing.generateKeyPair();
      expect(kp.publicKey.length, equals(1216));
      expect(kp.secretKey.length, equals(2464));
    });

    test('ct is 1120 bytes', () async {
      final PqcKeyPair kp = await xwing.generateKeyPair();
      final EncapsulationResult enc = await xwing.encaps(kp.publicKey);
      expect(enc.ciphertext.length, equals(1120));
    });

    test('deterministic seed96 produces same keypair', () async {
      final Uint8List seed = Uint8List(96)..fillRange(0, 96, 0x77);
      final PqcKeyPair kp1 = await xwing.generateKeyPair(seed);
      final PqcKeyPair kp2 = await xwing.generateKeyPair(seed);
      expect(kp1.publicKey, equals(kp2.publicKey));
      expect(kp1.secretKey, equals(kp2.secretKey));
    });

    test('different seeds produce different keys', () async {
      final Uint8List seed1 = Uint8List(96)..fillRange(0, 96, 0x11);
      final Uint8List seed2 = Uint8List(96)..fillRange(0, 96, 0x22);
      final PqcKeyPair kp1 = await xwing.generateKeyPair(seed1);
      final PqcKeyPair kp2 = await xwing.generateKeyPair(seed2);
      expect(kp1.publicKey, isNot(equals(kp2.publicKey)));
    });
  });

  // ── X-Wing cross-impl (pure Dart ↔ FFI) ──────────────────────────────────

  group('X-Wing cross-impl', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final XWingFfi xwingFfi;
    final XWingPureDart xwingPure = XWingPureDart.instance;

    setUpAll(() {
      if (ffiAvailable) xwingFfi = XWingFfi.fromLib(lib!);
    });

    test('pure-Dart encaps → FFI decaps', () async {
      final PqcKeyPair kp = await xwingFfi.generateKeyPair();
      final EncapsulationResult enc = await xwingPure.encaps(kp.publicKey);
      final Uint8List ss2 = await xwingFfi.decaps(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('FFI encaps → pure-Dart decaps', () async {
      final PqcKeyPair kp = await xwingFfi.generateKeyPair();
      final EncapsulationResult enc = await xwingFfi.encaps(kp.publicKey);
      final Uint8List ss2 =
          await xwingPure.decaps(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  // ── ML-DSA-65 (FFI) ───────────────────────────────────────────────────────

  group('ML-DSA-65 (FFI)', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final bool ffiAvailable = lib != null;
    late final MlDsa65Ffi dsa;

    setUpAll(() {
      if (ffiAvailable) dsa = MlDsa65Ffi.fromLib(lib!);
    });

    test('sign/verify round-trip', () async {
      final PqcKeyPair kp = await dsa.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('hello ml-dsa-65'.codeUnits);
      final Uint8List sig = await dsa.sign(kp.secretKey, msg);
      expect(await dsa.verify(kp.publicKey, msg, sig), isTrue);
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('tampered message fails verify', () async {
      final PqcKeyPair kp = await dsa.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('hello'.codeUnits);
      final Uint8List sig = await dsa.sign(kp.secretKey, msg);
      final Uint8List tampered = Uint8List.fromList('HELLO'.codeUnits);
      expect(await dsa.verify(kp.publicKey, tampered, sig), isFalse);
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('pk is 1952 bytes', () async {
      final PqcKeyPair kp = await dsa.generateKeyPair();
      expect(kp.publicKey.length, equals(1952));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('sk is 4032 bytes', () async {
      final PqcKeyPair kp = await dsa.generateKeyPair();
      expect(kp.secretKey.length, equals(4032));
    }, skip: ffiAvailable ? null : 'libcrypto not available');

    test('signature is at most 3309 bytes', () async {
      final PqcKeyPair kp = await dsa.generateKeyPair();
      final Uint8List sig =
          await dsa.sign(kp.secretKey, Uint8List.fromList([1, 2, 3]));
      expect(sig.length, lessThanOrEqualTo(3309));
    }, skip: ffiAvailable ? null : 'libcrypto not available');
  });

  // ── X-Wing resolver ────────────────────────────────────────────────────────

  group('X-Wing resolver', () {
    test('resolveXWing never throws', () {
      expect(() => resolveXWing(), returnsNormally);
    });

    test('resolveXWing round-trip works', () async {
      final XWingAlgorithm xwing = resolveXWing();
      final PqcKeyPair kp = await xwing.generateKeyPair();
      final EncapsulationResult enc = await xwing.encaps(kp.publicKey);
      final Uint8List ss2 = await xwing.decaps(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    });
  });

  // ── Resolver ───────────────────────────────────────────────────────────────

  group('resolver', () {
    test('resolveMlKem768 round-trip works', () async {
      final MlKem768Algorithm kem = resolveMlKem768();
      final PqcKeyPair kp = await kem.generateKeyPair();
      final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
      final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
      expect(enc.sharedSecret, equals(ss2));
    });

    test('resolveX25519 round-trip works', () async {
      final X25519Algorithm x25519 = resolveX25519();
      final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
          await x25519.generateKeyPair();
      final (publicKey: Uint8List bobPk, privateKey: Uint8List bobSk) =
          await x25519.generateKeyPair();
      final Uint8List ss1 = await x25519.dh(aliceSk, bobPk);
      final Uint8List ss2 = await x25519.dh(bobSk, alicePk);
      expect(ss1, equals(ss2));
    });

    test('resolveEd25519 sign/verify works', () async {
      final Ed25519Algorithm ed25519 = resolveEd25519();
      final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
          await ed25519.generateKeyPair();
      final Uint8List msg = Uint8List.fromList('test'.codeUnits);
      final Uint8List sig = await ed25519.sign(sk, msg);
      expect(await ed25519.verify(pk, msg, sig), isTrue);
    });
  });
}
