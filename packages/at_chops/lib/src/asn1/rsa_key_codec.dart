import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';

/// DER codec for the RSA key encodings the Atsign Protocol puts on the wire:
/// X.509 `SubjectPublicKeyInfo` for public keys and PKCS#8 `PrivateKeyInfo`
/// (wrapping a PKCS#1 `RSAPrivateKey`) for private keys — base64-encoded into
/// `AtPublicKey`/`AtPrivateKey` by callers.
///
/// Internal: the shape is fixed by data already in the field, so this is a
/// deliberately literal codec rather than a general ASN.1 layer.
class RsaKeyCodec {
  /// `1.2.840.113549.1.1.1` — PKCS#1 rsaEncryption.
  static const String _rsaEncryptionOid = '1.2.840.113549.1.1.1';

  /// `AlgorithmIdentifier { rsaEncryption, NULL }`, shared by both encodings.
  static ASN1Sequence _algorithmIdentifier() => ASN1Sequence(elements: [
        ASN1ObjectIdentifier.fromIdentifierString(_rsaEncryptionOid),
        ASN1Null(),
      ]);

  static ASN1Sequence _sequenceFrom(Uint8List der) =>
      ASN1Parser(der).nextObject() as ASN1Sequence;

  static BigInt _integerAt(ASN1Sequence sequence, int index) =>
      (sequence.elements![index] as ASN1Integer).integer!;

  /// Decodes an X.509 `SubjectPublicKeyInfo`.
  static RSAPublicKey decodePublicKey(Uint8List der) {
    final subjectPublicKey = _sequenceFrom(der).elements![1] as ASN1BitString;
    final rsaPublicKey =
        _sequenceFrom(Uint8List.fromList(subjectPublicKey.stringValues!));
    return RSAPublicKey(
        _integerAt(rsaPublicKey, 0), _integerAt(rsaPublicKey, 1));
  }

  /// Encodes an X.509 `SubjectPublicKeyInfo`.
  static Uint8List encodePublicKey(RSAPublicKey key) {
    final rsaPublicKey = ASN1Sequence(elements: [
      ASN1Integer(key.modulus!),
      ASN1Integer(key.exponent!),
    ]);
    return ASN1Sequence(elements: [
      _algorithmIdentifier(),
      ASN1BitString(stringValues: rsaPublicKey.encode()),
    ]).encode();
  }

  /// Decodes a PKCS#8 `PrivateKeyInfo`.
  ///
  /// `dP`, `dQ` and `qInv` in the PKCS#1 body are ignored: pointycastle
  /// recomputes the CRT values from `(n, d, p, q)`, so carrying them would only
  /// create a second source of truth.
  static RSAPrivateKey decodePrivateKey(Uint8List der) {
    final privateKey = _sequenceFrom(der).elements![2] as ASN1OctetString;
    final rsaPrivateKey = _sequenceFrom(privateKey.octets!);
    return RSAPrivateKey(
      _integerAt(rsaPrivateKey, 1), // modulus
      _integerAt(rsaPrivateKey, 3), // privateExponent
      _integerAt(rsaPrivateKey, 4), // p
      _integerAt(rsaPrivateKey, 5), // q
    );
  }

  /// Encodes a PKCS#8 `PrivateKeyInfo`.
  static Uint8List encodePrivateKey(RSAPrivateKey key) {
    final version = ASN1Integer(BigInt.zero);
    final privateExponent = key.privateExponent!;
    final p = key.p!;
    final q = key.q!;

    final rsaPrivateKey = ASN1Sequence(elements: [
      version,
      ASN1Integer(key.modulus!),
      ASN1Integer(key.publicExponent!),
      ASN1Integer(privateExponent),
      ASN1Integer(p),
      ASN1Integer(q),
      ASN1Integer(privateExponent % (p - BigInt.one)), // exponent1 (dP)
      ASN1Integer(privateExponent % (q - BigInt.one)), // exponent2 (dQ)
      ASN1Integer(q.modInverse(p)), // coefficient (qInv)
    ]);

    return ASN1Sequence(elements: [
      version,
      _algorithmIdentifier(),
      ASN1OctetString(octets: rsaPrivateKey.encode()),
    ]).encode();
  }
}
