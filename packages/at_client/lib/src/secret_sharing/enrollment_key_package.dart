import 'dart:convert' show base64Encode;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        AtKeysMaterial,
        CryptographicKeyType,
        KeyAlgorithmType;
import 'package:at_chops/at_chops.dart' show XWingPureDartAlgo;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, signEnvelope;
import 'package:meta/meta.dart' show experimental;

/// Builds the signed key package that rides an `enroll:request`, and records
/// its private half in the [AtKeys] the enrollment will persist.
///
/// Pass the result to `AtEnrollmentRequest.metadataBuilder`. It runs once, at
/// the only moment this is possible: the APKAM keypair exists (at_auth has
/// just generated it) and the enrollment record does not exist yet, so this
/// is the sole opportunity to put anything on it — the metadata is written by
/// the request that creates the record and never afterwards.
///
/// Two properties this relies on, both verified rather than assumed:
///
/// - **The X-Wing private half survives.** The material is added to the very
///   `AtKeys` at_auth carries forward and flushes into the app's `AtKeysIo` on
///   approval, so the private half lands in the same keyfile as the APKAM key.
///   Publishing an encapsulation target whose private half nobody kept would
///   leave every sender sealing to a key that can never be opened.
/// - **The package needs no enrollment id.** It is signed before the atServer
///   assigns one, and the payload never carried it — the enrollment record
///   does, and a reader injects it back. So the envelope omits the claim
///   rather than guessing at it; a verifier's authority is the signature
///   checking out against that record's own `_apsk`.
@experimental
Future<Map<String, dynamic>?> Function(AtKeysIo) enrollmentKeyPackageBuilder(
  String atSign, {
  DateTime? createdAt,
}) {
  return (AtKeysIo keysIo) async {
    final AtKeys keys = await keysIo.read(atSign);

    final apkamPublicKey = keys.apkamPublicKey;
    final apkamPrivateKey = keys.apkamPrivateKey;
    if (apkamPublicKey == null || apkamPrivateKey == null) {
      throw StateError(
          'enrollmentKeyPackageBuilder: no APKAM keypair in the AtKeys for '
          '$atSign, so the key package cannot be signed');
    }

    final xWing = await XWingPureDartAlgo.instance.generateKeyPair();
    final String pub = base64Encode(xWing.publicKey);
    final String kpid = PackageKey.computeKid(pub);
    final DateTime now = createdAt ?? DateTime.now().toUtc();

    // Both halves share the kpid as their keyId, which is what ties the
    // private half back to the package a sender sealed to.
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.publicEncapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(xWing.publicKey),
      createdAt: now,
    ));
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.privateDecapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(xWing.secretKey),
      createdAt: now,
    ));

    final payload = KeyPackage.payloadFor(
      createdAt: now,
      keys: [
        PackageKey(
          use: SecretSharingAlgos.useEnc,
          alg: SecretSharingAlgos.xWing,
          pub: pub,
        ),
      ],
    );

    return {
      'keyPackage': signEnvelope(
        payload,
        keys: ApkamSigningKeys(
          publicKey: apkamPublicKey.toString(),
          privateKey: apkamPrivateKey.toString(),
        ),
      ),
    };
  };
}
