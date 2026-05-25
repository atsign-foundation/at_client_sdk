import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

// ML-KEM-768 constants
const int mlKem768PkLen = 1184;
const int mlKem768SkLen = 2400;
const int mlKem768CtLen = 1088;
const int mlKem768SsLen = 32;

// FFI typedefs for liboqs ML-KEM-768
typedef KeypairNative = Int32 Function(Pointer<Uint8> pk, Pointer<Uint8> sk);
typedef KeypairDart = int Function(Pointer<Uint8> pk, Pointer<Uint8> sk);

typedef EncapsNative = Int32 Function(
    Pointer<Uint8> ct, Pointer<Uint8> ss, Pointer<Uint8> pk);
typedef EncapsDart = int Function(
    Pointer<Uint8> ct, Pointer<Uint8> ss, Pointer<Uint8> pk);

typedef DecapsNative = Int32 Function(
    Pointer<Uint8> ss, Pointer<Uint8> ct, Pointer<Uint8> sk);
typedef DecapsDart = int Function(
    Pointer<Uint8> ss, Pointer<Uint8> ct, Pointer<Uint8> sk);

class MlKem768 {
  final KeypairDart _keypair;
  final EncapsDart _encaps;
  final DecapsDart _decaps;

  MlKem768._(this._keypair, this._encaps, this._decaps);

  factory MlKem768.load(String dylibPath) {
    final lib = DynamicLibrary.open(dylibPath);
    return MlKem768._(
      lib.lookupFunction<KeypairNative, KeypairDart>(
          'OQS_KEM_ml_kem_768_keypair'),
      lib.lookupFunction<EncapsNative, EncapsDart>(
          'OQS_KEM_ml_kem_768_encaps'),
      lib.lookupFunction<DecapsNative, DecapsDart>(
          'OQS_KEM_ml_kem_768_decaps'),
    );
  }

  /// Generate a keypair. Returns (publicKey, secretKey).
  (Uint8List, Uint8List) keypair() {
    final pk = calloc<Uint8>(mlKem768PkLen);
    final sk = calloc<Uint8>(mlKem768SkLen);
    try {
      final rc = _keypair(pk, sk);
      if (rc != 0) throw StateError('ML-KEM-768 keypair failed (rc=$rc)');
      return (
        Uint8List.fromList(pk.asTypedList(mlKem768PkLen)),
        Uint8List.fromList(sk.asTypedList(mlKem768SkLen)),
      );
    } finally {
      calloc.free(pk);
      calloc.free(sk);
    }
  }

  /// Encapsulate against a public key. Returns (ciphertext, sharedSecret).
  (Uint8List, Uint8List) encaps(Uint8List publicKey) {
    final pkPtr = calloc<Uint8>(mlKem768PkLen);
    final ct = calloc<Uint8>(mlKem768CtLen);
    final ss = calloc<Uint8>(mlKem768SsLen);
    try {
      pkPtr.asTypedList(mlKem768PkLen).setAll(0, publicKey);
      final rc = _encaps(ct, ss, pkPtr);
      if (rc != 0) throw StateError('ML-KEM-768 encaps failed (rc=$rc)');
      return (
        Uint8List.fromList(ct.asTypedList(mlKem768CtLen)),
        Uint8List.fromList(ss.asTypedList(mlKem768SsLen)),
      );
    } finally {
      calloc.free(pkPtr);
      calloc.free(ct);
      calloc.free(ss);
    }
  }

  /// Decapsulate using a secret key. Returns shared secret.
  Uint8List decaps(Uint8List ciphertext, Uint8List secretKey) {
    final ctPtr = calloc<Uint8>(mlKem768CtLen);
    final skPtr = calloc<Uint8>(mlKem768SkLen);
    final ss = calloc<Uint8>(mlKem768SsLen);
    try {
      ctPtr.asTypedList(mlKem768CtLen).setAll(0, ciphertext);
      skPtr.asTypedList(mlKem768SkLen).setAll(0, secretKey);
      final rc = _decaps(ss, ctPtr, skPtr);
      if (rc != 0) throw StateError('ML-KEM-768 decaps failed (rc=$rc)');
      return Uint8List.fromList(ss.asTypedList(mlKem768SsLen));
    } finally {
      calloc.free(ctPtr);
      calloc.free(skPtr);
      calloc.free(ss);
    }
  }
}

String hex(Uint8List bytes, {int maxBytes = 16}) {
  final shown = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  final h = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  return bytes.length > maxBytes ? '$h... (${bytes.length} bytes)' : h;
}

Future<void> main() async {
  final dylibPath = p.join(
    p.dirname(Platform.script.toFilePath()),
    '..',
    'liboqs.dylib',
  );

  print('=== Hybrid PQC Key Exchange: X25519 + ML-KEM-768 ===\n');

  // ── Step 1: X25519 key exchange ──────────────────────────────────────────
  print('--- Step 1: X25519 ---');
  final x25519 = X25519();

  final aliceX25519 = await x25519.newKeyPair();
  final bobX25519 = await x25519.newKeyPair();

  final aliceX25519Pub = await aliceX25519.extractPublicKey();
  final bobX25519Pub = await bobX25519.extractPublicKey();

  final aliceSharedX25519 = await x25519.sharedSecretKey(
    keyPair: aliceX25519,
    remotePublicKey: bobX25519Pub,
  );
  final bobSharedX25519 = await x25519.sharedSecretKey(
    keyPair: bobX25519,
    remotePublicKey: aliceX25519Pub,
  );

  final aliceX25519Bytes =
      Uint8List.fromList(await aliceSharedX25519.extractBytes());
  final bobX25519Bytes =
      Uint8List.fromList(await bobSharedX25519.extractBytes());

  assert(aliceX25519Bytes.toString() == bobX25519Bytes.toString(),
      'X25519 shared secrets must match');
  print('Alice X25519 shared: ${hex(aliceX25519Bytes)}');
  print('Bob   X25519 shared: ${hex(bobX25519Bytes)}');
  print(
      'X25519 match: ${aliceX25519Bytes.toString() == bobX25519Bytes.toString()}\n');

  // ── Step 2: ML-KEM-768 KEM ───────────────────────────────────────────────
  print('--- Step 2: ML-KEM-768 (via FFI → liboqs) ---');
  final kem = MlKem768.load(dylibPath);

  // Bob generates ML-KEM-768 keypair
  final (bobMlKemPk, bobMlKemSk) = kem.keypair();
  print('Bob  ML-KEM-768 pk: ${hex(bobMlKemPk)}');

  // Alice encapsulates to Bob's public key
  final (ciphertext, aliceMlKemSs) = kem.encaps(bobMlKemPk);
  print('Ciphertext:          ${hex(ciphertext)}');
  print('Alice ML-KEM-768 ss: ${hex(aliceMlKemSs)}');

  // Bob decapsulates
  final bobMlKemSs = kem.decaps(ciphertext, bobMlKemSk);
  print('Bob   ML-KEM-768 ss: ${hex(bobMlKemSs)}');
  print(
      'ML-KEM-768 match:    ${aliceMlKemSs.toString() == bobMlKemSs.toString()}\n');

  // ── Step 3: Combine via HKDF-SHA256 ─────────────────────────────────────
  print('--- Step 3: HKDF-SHA256 (combine X25519 + ML-KEM-768 secrets) ---');

  // IKM = x25519_ss || mlkem_ss
  final ikm = Uint8List(aliceX25519Bytes.length + aliceMlKemSs.length);
  ikm.setAll(0, aliceX25519Bytes);
  ikm.setAll(aliceX25519Bytes.length, aliceMlKemSs);

  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final hybridKey = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: [], // empty salt → HKDF uses zeros
    info: 'hybrid-x25519-mlkem768'.codeUnits,
  );
  final hybridKeyBytes = Uint8List.fromList(await hybridKey.extractBytes());
  print('Hybrid key (Alice): ${hex(hybridKeyBytes, maxBytes: 32)}\n');

  // Bob derives the same key
  final ikmBob = Uint8List(bobX25519Bytes.length + bobMlKemSs.length);
  ikmBob.setAll(0, bobX25519Bytes);
  ikmBob.setAll(bobX25519Bytes.length, bobMlKemSs);

  final hybridKeyBob = await hkdf.deriveKey(
    secretKey: SecretKey(ikmBob),
    nonce: [],
    info: 'hybrid-x25519-mlkem768'.codeUnits,
  );
  final hybridKeyBobBytes =
      Uint8List.fromList(await hybridKeyBob.extractBytes());
  print('Hybrid key (Bob):   ${hex(hybridKeyBobBytes, maxBytes: 32)}');
  print(
      'Hybrid key match:   ${hybridKeyBytes.toString() == hybridKeyBobBytes.toString()}\n');

  // ── Step 4: AES-256-GCM encrypt/decrypt ─────────────────────────────────
  print('--- Step 4: AES-256-GCM ---');
  final aesGcm = AesGcm.with256bits();

  final secretKey = SecretKey(hybridKeyBytes);
  final nonce = aesGcm.newNonce();
  final plaintext =
      'Hello, post-quantum world! This message is protected by X25519 + ML-KEM-768.'
          .codeUnits;

  final encrypted = await aesGcm.encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: nonce,
  );

  print('Plaintext:  ${String.fromCharCodes(plaintext)}');
  print(
      'Ciphertext: ${hex(Uint8List.fromList(encrypted.cipherText))}');
  print(
      'MAC:        ${hex(Uint8List.fromList(encrypted.mac.bytes), maxBytes: 32)}');

  final decrypted = await aesGcm.decrypt(
    encrypted,
    secretKey: SecretKey(hybridKeyBobBytes),
  );

  print('Decrypted:  ${String.fromCharCodes(decrypted)}');
  print(
      'Decrypt OK: ${String.fromCharCodes(decrypted) == String.fromCharCodes(plaintext)}\n');

  // ── Step 5: SHA-256 session fingerprint ──────────────────────────────────
  print('--- Step 5: SHA-256 session fingerprint ---');
  final sha256 = Sha256();
  final sessionData = Uint8List.fromList([
    ...aliceX25519Bytes,
    ...aliceMlKemSs,
    ...hybridKeyBytes,
  ]);
  final fingerprint = await sha256.hash(sessionData);
  print(
      'Session fingerprint: ${hex(Uint8List.fromList(fingerprint.bytes), maxBytes: 32)}');

  print('\n=== All steps completed successfully ===');
}
