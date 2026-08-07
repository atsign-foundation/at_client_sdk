import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/asn1/rsa_key_codec.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/secure_random.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pointycastle/api.dart'
    show
        KeyParameter,
        ParametersWithRandom,
        PrivateKeyParameter,
        PublicKeyParameter;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

/// RSA (PKCS#1 v1.5) digital signatures.
///
/// The [hashingAlgoType] (SHA-256 or SHA-512) and [keySize] are algorithm
/// parameters fixed at construction; only key material is passed per call,
/// per the stateless [AtSignatureAlgorithm] contract. Key material is raw
/// DER bytes:
/// - `secretKey`: PKCS#8 DER-encoded private key
/// - `publicKey`: X.509 SubjectPublicKeyInfo DER-encoded public key
class RsaSigningAlgo implements AtSignatureAlgorithm {
  /// DER-encoded `DigestInfo` prefixes from RFC 8017 appendix B.1, which
  /// PKCS#1 v1.5 signatures wrap the digest in.
  static const String _sha256DigestIdentifier = '0609608648016503040201';
  static const String _sha512DigestIdentifier = '0609608648016503040203';

  /// The public exponent every atsign RSA key uses.
  static final BigInt _publicExponent = BigInt.from(65537);

  final HashingAlgoType _hashingAlgoType;
  final int _keySize;
  final String _name;

  @override
  String get name => _name;

  RsaSigningAlgo(
      {HashingAlgoType hashingAlgoType = HashingAlgoType.sha256,
      int keySize = 2048})
      : _hashingAlgoType = hashingAlgoType,
        _keySize = keySize,
        _name = keySize == 2048
            ? SigningAlgoType.rsa2048.name
            : SigningAlgoType.rsa4096.name;

  /// Generate a fresh RSA key pair of [keySize] bits.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final random = FortunaRandom()..seed(KeyParameter(secureRandomBytes(32)));
    final generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(_publicExponent, _keySize, 12), random));

    final keyPair = generator.generateKeyPair();
    return (
      publicKey: RsaKeyCodec.encodePublicKey(keyPair.publicKey),
      secretKey: RsaKeyCodec.encodePrivateKey(keyPair.privateKey),
    );
  }

  /// Sign [message] with the DER-encoded [secretKey].
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    final signer = _signer(() => AtSigningException(
        'Hashing algo $_hashingAlgoType is invalid/not supported'))
      ..init(
          true,
          PrivateKeyParameter<RSAPrivateKey>(
              RsaKeyCodec.decodePrivateKey(secretKey)));
    return signer.generateSignature(message).bytes;
  }

  /// Verify [signature] over [message] against the DER-encoded [publicKey].
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final signer = _signer(() => AtSigningVerificationException(
        'Invalid hashing algo $_hashingAlgoType provided'))
      ..init(
          false,
          PublicKeyParameter<RSAPublicKey>(
              RsaKeyCodec.decodePublicKey(publicKey)));
    return signer.verifySignature(message, RSASignature(signature));
  }

  /// A signer for [_hashingAlgoType], which must be SHA-256 or SHA-512 — the
  /// only two digests RSA signing supports here. Anything else throws whatever
  /// [unsupported] builds, so signing and verification each report their own
  /// exception type.
  RSASigner _signer(Exception Function() unsupported) =>
      switch (_hashingAlgoType) {
        HashingAlgoType.sha256 =>
          RSASigner(SHA256Digest(), _sha256DigestIdentifier),
        HashingAlgoType.sha512 =>
          RSASigner(SHA512Digest(), _sha512DigestIdentifier),
        _ => throw unsupported(),
      };
}
