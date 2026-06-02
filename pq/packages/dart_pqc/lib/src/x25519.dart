/// Pure-Dart X25519 Diffie-Hellman backed by the `cryptography` package.
///
/// This module wraps the X25519 algorithm from `package:cryptography` behind
/// the same [KemAlgorithm]-style interface used by the rest of dart_pqc,
/// expressed as an ephemeral KEM:
///
///   Alice:  generateKeyPair() → (pk_A, sk_A)
///   Bob:    encapsulate(pk_A)  → (ct = pk_B, ss = DH(sk_B, pk_A))
///   Alice:  decapsulate(sk_A, ct=pk_B) → ss = DH(sk_A, pk_B)
///
/// Note: [encapsulate] generates a fresh ephemeral key pair internally, so the
/// returned [EncapsulationResult.ciphertext] is Bob's ephemeral public key.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'dart_pqc_base.dart';

/// X25519 ECDH expressed as a KEM (ephemeral sender key pair).
final class X25519PureDart implements KemAlgorithm {
  /// Singleton instance — stateless, safe to share.
  static const X25519PureDart instance = X25519PureDart._();

  const X25519PureDart._();

  @override
  String get name => 'X25519';

  static final X25519 _x25519 = X25519();

  @override
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed]) async {
    // The cryptography package does not support seeded key generation for
    // X25519; the [seed] parameter is accepted for API consistency but ignored.
    final SimpleKeyPair kp = await _x25519.newKeyPair();
    final SimplePublicKey pub = await kp.extractPublicKey();
    final List<int> priv = await kp.extractPrivateKeyBytes();

    return PqcKeyPair(
      publicKey: Uint8List.fromList(pub.bytes),
      secretKey: Uint8List.fromList(priv),
    );
  }

  @override
  Future<EncapsulationResult> encapsulate(Uint8List publicKey) async {
    // Generate an ephemeral sender key pair.
    final SimpleKeyPair ephemeralKp = await _x25519.newKeyPair();
    final SimplePublicKey ephemeralPub = await ephemeralKp.extractPublicKey();

    // Recover the recipient's public key object.
    final SimplePublicKey recipientPub = SimplePublicKey(
      publicKey,
      type: KeyPairType.x25519,
    );

    // Perform the DH exchange: ss = DH(sk_ephemeral, pk_recipient).
    final SecretKey sharedSecretKey = await _x25519.sharedSecretKey(
      keyPair: ephemeralKp,
      remotePublicKey: recipientPub,
    );
    final List<int> ss = await sharedSecretKey.extractBytes();

    return EncapsulationResult(
      ciphertext: Uint8List.fromList(ephemeralPub.bytes),
      sharedSecret: Uint8List.fromList(ss),
    );
  }

  @override
  Future<Uint8List> decapsulate(Uint8List secretKey, Uint8List ciphertext) async {
    // Reconstruct the recipient key pair from the raw private key bytes.
    final SimpleKeyPairData recipientKp = SimpleKeyPairData(
      secretKey,
      publicKey: SimplePublicKey(const [], type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    // The ciphertext IS the sender's ephemeral public key.
    final SimplePublicKey senderPub = SimplePublicKey(
      ciphertext,
      type: KeyPairType.x25519,
    );

    final SecretKey sharedSecretKey = await _x25519.sharedSecretKey(
      keyPair: recipientKp,
      remotePublicKey: senderPub,
    );
    final List<int> ss = await sharedSecretKey.extractBytes();
    return Uint8List.fromList(ss);
  }
}
