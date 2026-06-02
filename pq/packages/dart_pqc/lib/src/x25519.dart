import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'dart_pqc_base.dart';

/// X25519 Diffie-Hellman key agreement — pure Dart, backed by package:cryptography.
final class X25519PureDart implements X25519Algorithm {
  static const X25519PureDart instance = X25519PureDart._();

  const X25519PureDart._();

  static final X25519 _x25519 = X25519();

  /// Generate a fresh X25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair() async {
    final SimpleKeyPair kp = await _x25519.newKeyPair();
    final SimplePublicKey pub = await kp.extractPublicKey();
    final List<int> priv = await kp.extractPrivateKeyBytes();
    return (
      publicKey: Uint8List.fromList(pub.bytes),
      privateKey: Uint8List.fromList(priv),
    );
  }

  /// Perform X25519 DH: compute the shared secret from [privateKey] and [peerPublicKey].
  ///
  /// Returns a 32-byte shared secret.
  Future<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey) async {
    final SimpleKeyPairData kp = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(const [], type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final SimplePublicKey peer = SimplePublicKey(
      peerPublicKey,
      type: KeyPairType.x25519,
    );
    final SecretKey ss = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: peer,
    );
    return Uint8List.fromList(await ss.extractBytes());
  }
}
