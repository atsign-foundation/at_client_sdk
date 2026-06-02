import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'dart_pqc_base.dart';

/// Ed25519 signing — pure Dart, backed by package:cryptography.
final class Ed25519PureDart implements Ed25519Algorithm {
  static const Ed25519PureDart instance = Ed25519PureDart._();

  const Ed25519PureDart._();

  static final Ed25519 _ed25519 = Ed25519();

  /// Generate a fresh Ed25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair() async {
    final SimpleKeyPair kp = await _ed25519.newKeyPair();
    final SimplePublicKey pub = await kp.extractPublicKey();
    final List<int> priv = await kp.extractPrivateKeyBytes();
    return (
      publicKey: Uint8List.fromList(pub.bytes),
      privateKey: Uint8List.fromList(priv),
    );
  }

  /// Sign [message] with [privateKey].
  ///
  /// Returns a 64-byte signature.
  Future<Uint8List> sign(Uint8List privateKey, Uint8List message) async {
    final SimpleKeyPairData kp = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(const [], type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final Signature sig = await _ed25519.sign(message, keyPair: kp);
    return Uint8List.fromList(sig.bytes);
  }

  /// Verify [signature] over [message] with [publicKey].
  ///
  /// Returns `true` if the signature is valid.
  Future<bool> verify(
      Uint8List publicKey, Uint8List message, Uint8List signature) async {
    final SimplePublicKey pub = SimplePublicKey(
      publicKey,
      type: KeyPairType.ed25519,
    );
    final Signature sig = Signature(signature, publicKey: pub);
    return _ed25519.verify(message, signature: sig);
  }
}
