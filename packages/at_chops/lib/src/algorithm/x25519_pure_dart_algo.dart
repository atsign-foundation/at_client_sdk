import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:cryptography/cryptography.dart';

/// X25519 Diffie–Hellman key agreement backed by pure-Dart
/// (`package:cryptography`).
///
/// Stateless — safe to share a single instance. Use [X25519FfiAlgo] when
/// hardware acceleration is desired and libcrypto is available.
final class X25519PureDartAlgo implements AtKeyAgreementAlgorithm {
  static const X25519PureDartAlgo instance = X25519PureDartAlgo._();

  const X25519PureDartAlgo._();

  static final X25519 _x25519 = X25519();

  /// Generate a fresh X25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  @override
  Future<({Uint8List publicKey, Uint8List privateKey})>
      generateKeyPair() async {
    final SimpleKeyPair kp = await _x25519.newKeyPair();
    final SimplePublicKey pub = await kp.extractPublicKey();
    final List<int> priv = await kp.extractPrivateKeyBytes();
    return (
      publicKey: Uint8List.fromList(pub.bytes),
      privateKey: Uint8List.fromList(priv),
    );
  }

  @override
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
