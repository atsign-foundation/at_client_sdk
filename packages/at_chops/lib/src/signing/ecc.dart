import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:crypto/crypto.dart';
import 'package:ecdsa/ecdsa.dart' as ecdsa;
import 'package:elliptic/elliptic.dart' as elliptic;

/// ECDSA over secp256r1 (P-256) with SHA-256 digests.
///
/// Implements the stateless [AtSignatureAlgorithm] contract — all key
/// material is passed per call as raw bytes:
/// - `secretKey`: the 32-byte big-endian private scalar
/// - `publicKey`: the uncompressed SEC1 point (65 bytes: `0x04 ‖ X ‖ Y`)
/// - signatures are 64-byte compact `R ‖ S`
class EccSigningAlgo implements AtSignatureAlgorithm {
  final elliptic.Curve _curve = elliptic.getSecp256r1();
  @override
  String get name => SigningAlgoType.eccSecp256r1.name;
  EccSigningAlgo();

  /// Generate a fresh secp256r1 key pair.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final privateKey = _curve.generatePrivateKey();
    return (
      publicKey: _hexToBytes(privateKey.publicKey.toHex()),
      secretKey: Uint8List.fromList(privateKey.bytes),
    );
  }

  /// Sign [message] with the 32-byte [secretKey] scalar; returns 64-byte
  /// compact `R ‖ S`.
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    final privateKey = elliptic.PrivateKey.fromBytes(_curve, secretKey);
    final signature = ecdsa.signature(privateKey, _sha256(message));
    return Uint8List.fromList(signature.toCompact());
  }

  /// Verify the 64-byte compact [signature] over [message] against the
  /// uncompressed [publicKey].
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final pubKey = elliptic.PublicKey.fromHex(_curve, _bytesToHex(publicKey));
    final eccSignature = ecdsa.Signature.fromCompact(signature);
    return ecdsa.verify(pubKey, _sha256(message), eccSignature);
  }

  List<int> _sha256(Uint8List data) => sha256.convert(data).bytes;

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
