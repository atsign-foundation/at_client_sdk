import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/key/keys.dart';
import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';

/// RSASSA-PKCS1-v1_5 signing and verification with all key material passed
/// per call. Safe to share as a singleton.
///
/// Key material is DER, matching what [RsaKeyPair] stores base64-encoded — so
/// an existing key pair crosses over with a `base64Decode`:
///
/// ```dart
/// final sig = await RsaSignatureAlgo.rsa2048()
///     .signBytes(message, secretKey: base64Decode(kp.atPrivateKey.privateKey));
/// ```
///
/// [publicKey] bytes are an X.509 `SubjectPublicKeyInfo`; [secretKey] bytes are
/// a PKCS#8 `PrivateKeyInfo`.
///
/// The modulus size is fixed per instance rather than read off the key, because
/// [signingAlgoType] has to answer before any key is in scope. That is also what
/// makes [generateKeyPair] unambiguous, and it lets [signBytes] reject a key
/// whose size contradicts the identifier this instance reports — the alternative
/// is a signature that goes on the wire under the wrong label.
///
/// Note `SigningAlgoType.rsa4096` is not in the atServer's `pkam:` grammar,
/// which accepts only `ecc_secp256r1`, `rsa2048`, and `mldsa65`. An
/// [RsaSignatureAlgo.rsa4096] instance is usable for data and envelope
/// signing, but not for PKAM authentication.
///
/// [generateKeyPair] runs RSA key generation on the calling isolate, so it
/// blocks the event loop while it runs. It is a probabilistic prime search with
/// a long tail — usually well under a second at 4096 bits, but occasionally
/// much longer. Prefer generating once and persisting over generating per
/// operation, and run it off the UI isolate.
final class RsaSignatureAlgo implements AtSignatureAlgorithm {
  final SigningAlgoType signingAlgoType;
  String get name => signingAlgoType.name;

  /// Digest used by the PKCS#1 v1.5 construction, and the value for the wire's
  /// `hashingAlgo` field. Always [HashingAlgoType.sha256] or
  /// [HashingAlgoType.sha512].
  final HashingAlgoType hashingAlgoType;

  final int _modulusBits;

  RsaSignatureAlgo._(
      this.signingAlgoType, this._modulusBits, this.hashingAlgoType) {
    if (hashingAlgoType != HashingAlgoType.sha256 &&
        hashingAlgoType != HashingAlgoType.sha512) {
      throw AtSigningException(
          'Hashing algo $hashingAlgoType is invalid/not supported for RSA '
          'signing — use sha256 or sha512');
    }
  }

  /// 2048-bit RSA. The only RSA size the `pkam:` verb accepts.
  RsaSignatureAlgo.rsa2048({HashingAlgoType hashing = HashingAlgoType.sha256})
      : this._(SigningAlgoType.rsa2048, 2048, hashing);

  /// 4096-bit RSA. Not accepted by the `pkam:` verb — data and envelope
  /// signing only.
  RsaSignatureAlgo.rsa4096({HashingAlgoType hashing = HashingAlgoType.sha256})
      : this._(SigningAlgoType.rsa4096, 4096, hashing);

  /// Generate a fresh key pair of this instance's modulus size.
  ///
  /// Returns DER bytes: `publicKey` as X.509 `SubjectPublicKeyInfo`,
  /// `secretKey` as PKCS#8 `PrivateKeyInfo`.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final RSAKeypair kp = RSAKeypair.fromRandom(keySize: _modulusBits);
    return (
      publicKey: base64Decode(kp.publicKey.toString()),
      secretKey: base64Decode(kp.privateKey.toString()),
    );
  }

  /// Sign [message] with [secretKey] (PKCS#8 DER).
  ///
  /// Throws [AtSigningException] if [secretKey] is not parseable, or if its
  /// modulus size differs from this instance's — signing with a mismatched key
  /// would label the signature with the wrong [signingAlgoType].
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    final RSAPrivateKey key = _parsePrivateKey(secretKey);
    return switch (hashingAlgoType) {
      HashingAlgoType.sha256 => key.createSHA256Signature(message),
      HashingAlgoType.sha512 => key.createSHA512Signature(message),
      // Unreachable — the constructor admits only the two above. Throwing
      // rather than falling back to sha256 keeps an unexpected digest from
      // being signed under the wrong hashingAlgoType.
      _ => throw AtSigningException(
          'Hashing algo $hashingAlgoType is invalid/not supported'),
    };
  }

  /// Verify [signature] over [message] against [publicKey] (X.509 DER).
  ///
  /// Throws [AtSigningVerificationException] if [publicKey] is not parseable,
  /// or if its modulus size differs from this instance's — a key of another
  /// size was not produced by the algorithm this instance claims to be.
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final RSAPublicKey key = _parsePublicKey(publicKey);
    return switch (hashingAlgoType) {
      HashingAlgoType.sha256 => key.verifySHA256Signature(message, signature),
      HashingAlgoType.sha512 => key.verifySHA512Signature(message, signature),
      // Unreachable — see signBytes.
      _ => throw AtSigningVerificationException(
          'Invalid hashing algo $hashingAlgoType provided'),
    };
  }

  RSAPrivateKey _parsePrivateKey(Uint8List der) {
    final RSAPrivateKey key;
    try {
      key = RSAPrivateKey.fromString(base64Encode(der));
    } catch (e) {
      throw AtSigningException(
          'secretKey is not a readable RSA private key. Expected the raw DER '
          'bytes of a PKCS#8 PrivateKeyInfo — if what you hold is a base64 '
          'string (RsaKeyPair.atPrivateKey.privateKey, or the contents of a '
          '.atKeys file), base64Decode it first. Parse error: $e');
    }
    final int bits = key.asPointyCastle.n!.bitLength;
    if (bits != _modulusBits) {
      throw AtSigningException('Cannot sign with a $bits-bit key using '
          'RsaSignatureAlgo.${signingAlgoType.name} — the signature would go '
          'on the wire labelled ${signingAlgoType.name}. Construct the '
          'RsaSignatureAlgo whose name matches the key you hold.');
    }
    return key;
  }

  RSAPublicKey _parsePublicKey(Uint8List der) {
    final RSAPublicKey key;
    try {
      key = RSAPublicKey.fromString(base64Encode(der));
    } catch (e) {
      throw AtSigningVerificationException(
          'publicKey is not a readable RSA public key. Expected the raw DER '
          'bytes of an X.509 SubjectPublicKeyInfo — if what you hold is a '
          'base64 string (RsaKeyPair.atPublicKey.publicKey), base64Decode it '
          'first. Parse error: $e');
    }
    final int bits = key.asPointyCastle.modulus!.bitLength;
    if (bits != _modulusBits) {
      throw AtSigningVerificationException(
          'Cannot verify with a $bits-bit key using '
          'RsaSignatureAlgo.${signingAlgoType.name} — a key of another size '
          'was not produced by the algorithm this instance claims to be. '
          'Construct the RsaSignatureAlgo whose name matches the key you '
          'hold.');
    }
    return key;
  }
}

/// Data signing and verification using atsign encryption keypair
/// Allowed algorithms are listed in [SigningAlgoType] and [HashingAlgoType]
@Deprecated('Use RsaSignatureAlgo instead. This implements the deprecated '
    'AtSigningAlgorithm interface and will be removed in the next major '
    'release.')
class RsaSigningAlgo implements AtSigningAlgorithm {
  final AsymmetricKeyPair? _encryptionKeyPair;
  final HashingAlgoType _hashingAlgoType;

  RsaSigningAlgo(this._encryptionKeyPair, this._hashingAlgoType);

  @override
  Uint8List sign(Uint8List data) {
    if (_encryptionKeyPair == null) {
      throw AtSigningException(
          'encryption key pair not set for rsa signing algo');
    }
    final rsaPrivateKey =
        RSAPrivateKey.fromString(_encryptionKeyPair.atPrivateKey.privateKey);
    switch (_hashingAlgoType) {
      case HashingAlgoType.sha256:
        return rsaPrivateKey.createSHA256Signature(data);
      case HashingAlgoType.sha512:
        return rsaPrivateKey.createSHA512Signature(data);
      default:
        throw AtSigningException(
            'Hashing algo $_hashingAlgoType is invalid/not supported');
    }
  }

  @override
  bool verify(Uint8List signedData, Uint8List signature, {String? publicKey}) {
    RSAPublicKey? rsaPublicKey;
    if (publicKey != null) {
      rsaPublicKey = RSAPublicKey.fromString(publicKey);
    } else if (_encryptionKeyPair != null) {
      rsaPublicKey =
          RSAPublicKey.fromString(_encryptionKeyPair.atPublicKey.publicKey);
    } else {
      throw AtSigningVerificationException(
          'Encryption key pair or public key not set for default signing algo');
    }
    switch (_hashingAlgoType) {
      case HashingAlgoType.sha256:
        return rsaPublicKey.verifySHA256Signature(signedData, signature);
      case HashingAlgoType.sha512:
        return rsaPublicKey.verifySHA512Signature(signedData, signature);
      default:
        throw AtSigningVerificationException(
            'Invalid hashing algo $_hashingAlgoType provided');
    }
  }
}
