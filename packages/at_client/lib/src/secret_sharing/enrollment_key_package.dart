import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole;
import 'package:at_chops/at_chops.dart' show AtKemAlgorithm, SigningAlgoType;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, EnvelopeType, signEnvelope;
import 'package:meta/meta.dart' show experimental;

/// Builds the signed key package that rides an `enroll:request`, and records
/// its private half in the [AtKeys] the enrollment will persist.
///
/// Pass the result to `AtEnrollmentRequest.metadataBuilder`; it decides the
/// key the enrollment advertises until its first startup, after which
/// `KeyPackageMinting` reconciles `metadata.keyPackage` against the configured
/// list. The KEM private half is added to the [AtKeys] at_auth flushes into the
/// app's [AtKeysIo] on approval, landing in the same keyfile as the APKAM key,
/// and the envelope omits the enrollment id because it is signed before the
/// atServer assigns one.
///
/// [signingAlgo] is the algorithm of the APKAM keypair the handed [AtKeys]
/// carries, and therefore how the envelope is signed. [keyEstablishmentAlgo]
/// is the KEM the encapsulation key is minted under: pass the **first** of
/// `AtClientPreference.keyEstablishmentAlgorithms`, since an enrollment is
/// created holding one key and the rest of that list is minted at the client's
/// first startup.
@experimental
Future<Map<String, dynamic>?> Function(AtKeysIo) enrollmentKeyPackageBuilder(
  String atSign, {
  DateTime? createdAt,
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  String keyEstablishmentAlgo = SecretSharingAlgos.xWing,
  ({
    SigningAlgoType algorithm,
    String publicKey,
    String privateKey
  })? advertisedSigningKey,
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

    final AtKemAlgorithm? kem = SecretSharingAlgos.kemFor(keyEstablishmentAlgo);
    final CryptographicMaterialAlgorithm? materialAlgo =
        SecretSharingAlgos.materialAlgoFor(keyEstablishmentAlgo);
    if (kem == null || materialAlgo == null) {
      throw StateError('enrollmentKeyPackageBuilder: no implementation for '
          '"$keyEstablishmentAlgo". This is the only moment an enrollment\'s '
          'encapsulation target can be set without the enrollment itself later '
          'sending enroll:update, so it fails rather than quietly minting '
          'something else. '
          'Supported: ${SecretSharingAlgos.keyAlgos}');
    }

    // NOTE: the SEED is filed, not the secret key. They are the same bytes for
    // X-Wing, but ML-KEM's secret key is an expanded decapsulation key that
    // nothing turns back into a public half, so a keyfile holding one could
    // never recover the package it was filed for.
    final Uint8List seed = kem.newSeed();
    final pair = await kem.keyPairFromSeed(seed);
    final String pub = base64Encode(pair.publicKey);
    final String kpid = PackageKey.computeKid(pub);
    final DateTime now = createdAt ?? DateTime.now().toUtc();

    // NOTE: both halves share the kpid as their keyId, which is what ties the
    // private half back to the package a sender sealed to.
    keys.addKey(CryptographicMaterial(
      keyId: kpid,
      role: CryptographicMaterialRole.publicEncapsulation,
      algorithm: materialAlgo,
      bytes: AtBytes(pair.publicKey),
      createdAt: now,
    ));
    keys.addKey(CryptographicMaterial(
      keyId: kpid,
      role: CryptographicMaterialRole.privateDecapsulation,
      algorithm: materialAlgo,
      bytes: AtBytes(seed),
      createdAt: now,
    ));

    final payload = KeyPackage.payloadFor(
      createdAt: now,
      keys: [
        PackageKey(
          use: SecretSharingAlgos.useEnc,
          alg: keyEstablishmentAlgo,
          pub: pub,
        ),
      ],
    );

    return {
      // NOTE: toJson, not the envelope itself — this map is
      // `EnrollParams.metadata`, read back as a Map by every consumer, and a
      // Dart object here reaches every in-process reader as something they
      // cannot index.
      'keyPackage': signEnvelope(
        payload,
        type: EnvelopeType.keyPackage,
        // NOTE: whichever key `_apsk` will advertise must be the one that signs
        // here. A peer verifies this package against that record before sealing
        // any secret to the enrollment, so the two disagreeing means the
        // enrollment is created and then receives nothing. The APKAM key signs
        // only while the enrollment has no signing key of its own, which is
        // also the only time `_apsk` names it.
        keys: [
          if (advertisedSigningKey case final signing?)
            ApkamSigningKeys(
              algorithm: signing.algorithm,
              publicKey: signing.publicKey,
              privateKey: signing.privateKey,
            )
          else
            ApkamSigningKeys(
              algorithm: signingAlgo,
              publicKey: apkamPublicKey.toString(),
              privateKey: apkamPrivateKey.toString(),
            )
        ],
      ).toJson(),
    };
  };
}
