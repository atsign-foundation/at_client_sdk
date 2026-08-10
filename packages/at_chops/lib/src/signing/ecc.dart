import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/secure_random.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pointycastle/api.dart'
    show
        AsymmetricKeyPair,
        KeyParameter,
        ParametersWithRandom,
        PrivateKeyParameter,
        PublicKeyParameter;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';

/// ECDSA over secp256r1 (P-256) with SHA-256 digests.
///
/// Implements the stateless [AtSignatureAlgorithm] contract — all key
/// material is passed per call as raw bytes:
/// - `secretKey`: the 32-byte big-endian private scalar
/// - `publicKey`: the uncompressed SEC1 point (65 bytes: `0x04 ‖ X ‖ Y`)
/// - signatures are 64-byte compact `R ‖ S`
///
/// Nonces are derived per RFC 6979, so signing is deterministic: the same
/// (key, message) always yields the same signature, and a weak platform RNG
/// cannot leak the private key through a repeated nonce.
class EccSigningAlgo implements AtSignatureAlgorithm {
  /// Both halves of a compact signature, and the private scalar, are exactly
  /// this wide — the curve's order is 256 bits.
  static const int _scalarLength = 32;

  final ECDomainParameters _domain = ECCurve_secp256r1();

  @override
  String get name => SigningAlgoType.eccSecp256r1.name;

  EccSigningAlgo();

  /// Generate a fresh secp256r1 key pair.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final random = FortunaRandom()..seed(KeyParameter(secureRandomBytes(32)));
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_domain), random));

    final AsymmetricKeyPair keyPair = generator.generateKeyPair();
    return (
      publicKey: (keyPair.publicKey as ECPublicKey).Q!.getEncoded(false),
      secretKey: _encodeScalar((keyPair.privateKey as ECPrivateKey).d!),
    );
  }

  /// Sign [message] with the 32-byte [secretKey] scalar; returns 64-byte
  /// compact `R ‖ S`.
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    // The HMAC-SHA256 argument is what selects RFC 6979 nonce derivation; it
    // must use the same digest as the one hashing the message.
    final signer = ECDSASigner(SHA256Digest(), HMac.withDigest(SHA256Digest()))
      ..init(
          true,
          PrivateKeyParameter<ECPrivateKey>(
              ECPrivateKey(_decodeScalar(secretKey), _domain)));

    final signature = signer.generateSignature(message) as ECSignature;
    return Uint8List(_scalarLength * 2)
      ..setRange(0, _scalarLength, _encodeScalar(signature.r))
      ..setRange(_scalarLength, _scalarLength * 2, _encodeScalar(signature.s));
  }

  /// Verify the 64-byte compact [signature] over [message] against the
  /// uncompressed [publicKey].
  ///
  /// Throws [AtSigningVerificationException] if the signature does not verify.
  @override
  Future<void> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final signer = ECDSASigner(SHA256Digest())
      ..init(
          false,
          PublicKeyParameter<ECPublicKey>(
              ECPublicKey(_domain.curve.decodePoint(publicKey), _domain)));

    final verified = signer.verifySignature(
        message,
        ECSignature(_decodeScalar(signature.sublist(0, _scalarLength)),
            _decodeScalar(signature.sublist(_scalarLength))));
    if (!verified) {
      throw AtSigningVerificationException(
          '$name signature verification failed');
    }
  }

  /// [value] as [_scalarLength] big-endian bytes, zero-padded on the left.
  static Uint8List _encodeScalar(BigInt value) {
    final out = Uint8List(_scalarLength);
    var remaining = value;
    for (var i = _scalarLength - 1; i >= 0; i--) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return out;
  }

  static BigInt _decodeScalar(Uint8List bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }
}
