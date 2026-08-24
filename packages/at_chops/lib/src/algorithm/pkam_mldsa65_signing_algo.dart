import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/key/impl/at_pkam_key_pair.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_pure_dart.dart';

/// PKAM signing and verification with an ML-DSA-65 (FIPS 204) APKAM keypair.
///
/// The mldsa65 counterpart of `PkamSigningAlgo`, for enrollments whose
/// record says `signingAlgo:mldsa65`. Key material rides the same
/// String-typed [AtPkamKeyPair] slot the RSA path uses, carrying base64 of
/// the RAW ML-DSA keys (1952-byte public, 4032-byte secret) rather than PEM.
/// ML-DSA signs the message directly — there is no separate hashing step, so
/// no `HashingAlgoType` is taken.
///
/// Synchronous by design: `AtChops.sign` is synchronous and the pure-Dart
/// ML-DSA computation is too — this class exists because the
/// [AtSignatureAlgorithm] implementations wrap that computation in `Future`s
/// the synchronous dispatch cannot await.
///
/// Despite the name, `AtChopsImpl`'s VERIFICATION dispatch also resolves
/// non-pkam-mode mldsa65 input here (with an explicit `publicKey:` and no
/// keypair), so data-mode ML-DSA verification lands on this class too.
@Deprecated(
    'Constructed by AtChopsImpl\'s deprecated dispatch; not an API to build '
    'on. Direct callers should use MlDsa65PureDartAlgo.signBytesSync / '
    'verifyBytesSync with explicit key material. This compatibility API '
    'will be removed in the next major release.')
class PkamMlDsa65SigningAlgo implements AtSigningAlgorithm {
  final AtPkamKeyPair? _pkamKeyPair;

  PkamMlDsa65SigningAlgo(this._pkamKeyPair);

  @override
  Uint8List sign(Uint8List data) {
    if (_pkamKeyPair == null) {
      throw AtSigningException('pkam key pair is null. cannot sign data');
    }
    final Uint8List secretKey;
    try {
      secretKey = base64Decode(_pkamKeyPair.atPrivateKey.privateKey);
    } on FormatException {
      throw AtSigningException(
          'an mldsa65 PKAM private key must be base64 of the raw '
          'ML-DSA-65 secret key');
    }
    return MlDsa65PureDartAlgo.signBytesSync(data, secretKey: secretKey);
  }

  @override
  bool verify(Uint8List signedData, Uint8List signature, {String? publicKey}) {
    final b64 = publicKey ?? _pkamKeyPair?.atPublicKey.publicKey;
    if (b64 == null) {
      throw AtSigningVerificationException(
          'Pkam key pair or public key not set for pkam verification');
    }
    final Uint8List publicKeyBytes;
    try {
      publicKeyBytes = base64Decode(b64);
    } on FormatException {
      throw AtSigningVerificationException(
          'an mldsa65 PKAM public key must be base64 of the raw '
          'ML-DSA-65 public key');
    }
    return MlDsa65PureDartAlgo.verifyBytesSync(signedData,
        signature: signature, publicKey: publicKeyBytes);
  }
}
