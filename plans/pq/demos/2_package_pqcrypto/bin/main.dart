import 'dart:typed_data';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:cryptography/cryptography.dart';

String hex(Uint8List bytes, {int maxBytes = 16}) {
  final shown = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  final h = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  return bytes.length > maxBytes ? '$h... (${bytes.length} bytes)' : h;
}

Future<void> main() async {
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

  // ── Step 2: ML-KEM-768 KEM (via pqcrypto) ───────────────────────────────
  print('--- Step 2: ML-KEM-768 (via pqcrypto) ---');
  final kem = PqcKem.kyber768;

  // Bob generates ML-KEM-768 keypair
  final (bobMlKemPk, bobMlKemSk) = kem.generateKeyPair();
  print('Bob  ML-KEM-768 pk: ${hex(Uint8List.fromList(bobMlKemPk))}');

  // Alice encapsulates to Bob's public key
  final (ciphertext, aliceMlKemSs) = kem.encapsulate(bobMlKemPk);
  print('Ciphertext:          ${hex(Uint8List.fromList(ciphertext))}');
  print('Alice ML-KEM-768 ss: ${hex(Uint8List.fromList(aliceMlKemSs))}');

  // Bob decapsulates
  final bobMlKemSs = kem.decapsulate(bobMlKemSk, ciphertext);
  print('Bob   ML-KEM-768 ss: ${hex(Uint8List.fromList(bobMlKemSs))}');
  print(
      'ML-KEM-768 match:    ${aliceMlKemSs.toString() == bobMlKemSs.toString()}\n');

  // ── Step 3: Combine via HKDF-SHA256 ─────────────────────────────────────
  print('--- Step 3: HKDF-SHA256 (combine X25519 + ML-KEM-768 secrets) ---');

  // IKM = mlkem_ss || x25519_ss  (ML-KEM first, per X25519MLKEM768 spec)
  final ikm = Uint8List(aliceMlKemSs.length + aliceX25519Bytes.length);
  ikm.setAll(0, aliceMlKemSs);
  ikm.setAll(aliceMlKemSs.length, aliceX25519Bytes);

  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final hybridKey = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: [],
    info: 'hybrid-x25519-mlkem768'.codeUnits,
  );
  final hybridKeyBytes = Uint8List.fromList(await hybridKey.extractBytes());
  print('Hybrid key (Alice): ${hex(hybridKeyBytes, maxBytes: 32)}\n');

  // Bob derives the same key
  final ikmBob = Uint8List(bobMlKemSs.length + bobX25519Bytes.length);
  ikmBob.setAll(0, bobMlKemSs);
  ikmBob.setAll(bobMlKemSs.length, bobX25519Bytes);

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
  print('Ciphertext: ${hex(Uint8List.fromList(encrypted.cipherText))}');
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
