// Crypto primitive wrappers. Used by ratchet.dart.
//
// Layers wrapped:
//   X25519        → key agreement (cryptography package)
//   Ed25519       → SPK signature (cryptography package)
//   ML-KEM-768    → post-quantum KEM (pqcrypto package)
//   HKDF-SHA256   → key derivation (cryptography package)
//   HMAC-SHA256   → chain key step (cryptography package)
//   AES-256-GCM   → bulk encryption (cryptography package)

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

/// HKDF-SHA256 used at PQXDH session init.
/// salt = empty, info = "pq-chat-init", output = 32B (initial rootKey).
Future<Uint8List> hkdfInit(Uint8List ikm) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: const <int>[],
    info: 'pq-chat-init'.codeUnits,
  );
  return Uint8List.fromList(await derived.extractBytes());
}

/// HKDF-SHA256 used at every ratchet step.
/// salt = current rootKey, info = "pq-chat-ratchet", output = 64B = newRootKey ‖ chainKey.
Future<Uint8List> hkdfRkStep(Uint8List rootKey, Uint8List ikm) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: rootKey,
    info: 'pq-chat-ratchet'.codeUnits,
  );
  return Uint8List.fromList(await derived.extractBytes());
}

/// Symmetric chain step: HMAC(ck, 0x01) → msg_key, HMAC(ck, 0x02) → next ck.
Future<(Uint8List, Uint8List)> chainStep(Uint8List ck) async {
  final hmac = Hmac.sha256();
  final mk = await hmac.calculateMac([0x01], secretKey: SecretKey(ck));
  final nck = await hmac.calculateMac([0x02], secretKey: SecretKey(ck));
  return (Uint8List.fromList(mk.bytes), Uint8List.fromList(nck.bytes));
}

Future<Uint8List> x25519Dh(SimpleKeyPairData mySkKp, Uint8List peerPk) async {
  final ss = await X25519().sharedSecretKey(
    keyPair: mySkKp,
    remotePublicKey: SimplePublicKey(peerPk, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await ss.extractBytes());
}

Future<(Uint8List, Uint8List, Uint8List)> aesSeal(
    Uint8List key, Uint8List plaintext) async {
  final gcm = AesGcm.with256bits();
  final nonce = Uint8List.fromList(gcm.newNonce());
  final box = await gcm.encrypt(plaintext,
      secretKey: SecretKey(key), nonce: nonce);
  return (
    nonce,
    Uint8List.fromList(box.cipherText),
    Uint8List.fromList(box.mac.bytes),
  );
}

Future<Uint8List> aesOpen(
    Uint8List key, Uint8List nonce, Uint8List ct, Uint8List mac) async {
  final pt = await AesGcm.with256bits().decrypt(
    SecretBox(ct, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
  );
  return Uint8List.fromList(pt);
}

/// ML-KEM-768 encaps. Wrapper to keep the signature explicit.
(Uint8List ct, Uint8List ss) mlKemEncaps(Uint8List peerPk) {
  final (ct, ss) = PqcKem.kyber768.encapsulate(peerPk);
  return (Uint8List.fromList(ct), Uint8List.fromList(ss));
}

/// ML-KEM-768 decaps.
Uint8List mlKemDecaps(Uint8List ourSk, Uint8List ct) {
  return Uint8List.fromList(PqcKem.kyber768.decapsulate(ourSk, ct));
}

/// ML-KEM-768 keypair generation. Returns (pk, sk).
(Uint8List pk, Uint8List sk) mlKemGenerateKeyPair() {
  final (pk, sk) = PqcKem.kyber768.generateKeyPair();
  return (Uint8List.fromList(pk), Uint8List.fromList(sk));
}

bool bytesEq(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
