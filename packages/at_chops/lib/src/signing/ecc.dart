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
/// - signatures are the compact `R ‖ S` pair, ASCII-hex encoded (128 bytes)
///   — the format at_chops 3.x wrote to the wire
///   (`ecdsa.Signature.toCompactHex().codeUnits`). [verifyBytes] also accepts
///   the raw 64-byte compact form, so data signed either way still verifies.
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
  String get name => SigningAlgoType.ecc_secp256r1.name;

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

  /// Sign [message] with the 32-byte [secretKey] scalar; returns the compact
  /// `R ‖ S` pair ASCII-hex encoded (128 bytes) — the at_chops 3.x wire
  /// format.
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
    final compact = Uint8List(_scalarLength * 2)
      ..setRange(0, _scalarLength, _encodeScalar(signature.r))
      ..setRange(_scalarLength, _scalarLength * 2, _encodeScalar(signature.s));
    return Uint8List.fromList(_bytesToHex(compact).codeUnits);
  }

  /// Verify [signature] over [message] against the uncompressed [publicKey].
  ///
  /// Accepts both the 128-byte ASCII-hex encoding [signBytes] writes (the
  /// at_chops 3.x wire format) and the raw 64-byte compact `R ‖ S` form, so
  /// data signed under either encoding still verifies.
  ///
  /// Throws [AtSigningVerificationException] if the signature does not
  /// verify, or [ArgumentError] if [signature] is neither 64 nor 128 bytes.
  @override
  Future<void> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final Uint8List compact;
    if (signature.length == _scalarLength * 2) {
      compact = signature;
    } else if (signature.length == _scalarLength * 4) {
      compact = _hexToBytes(String.fromCharCodes(signature));
    } else {
      throw ArgumentError.value(signature.length, 'signature.length',
          'must be ${_scalarLength * 2} (compact) or ${_scalarLength * 4} (hex)');
    }

    final signer = ECDSASigner(SHA256Digest())
      ..init(
          false,
          PublicKeyParameter<ECPublicKey>(
              ECPublicKey(_domain.curve.decodePoint(publicKey), _domain)));

    final verified = signer.verifySignature(
        message,
        ECSignature(_decodeScalar(compact.sublist(0, _scalarLength)),
            _decodeScalar(compact.sublist(_scalarLength))));
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

  // Not dart:core's StringBuffer: `at_commons.dart` exports its own class of
  // that name (an AtBuffer<String>, `append`-based) which shadows it here.
  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
