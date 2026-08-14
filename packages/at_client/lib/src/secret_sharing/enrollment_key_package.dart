import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        AtKeysMaterial,
        CryptographicKeyType;
import 'package:at_chops/at_chops.dart' show AtKemAlgorithm, SigningAlgoType;
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
/// - **The KEM private half survives.** The material is added to the very
///   `AtKeys` at_auth carries forward and flushes into the app's `AtKeysIo` on
///   approval, so the private half lands in the same keyfile as the APKAM key.
///   Publishing an encapsulation target whose private half nobody kept would
///   leave every sender sealing to a key that can never be opened.
/// - **The package needs no enrollment id.** It is signed before the atServer
///   assigns one, and the payload never carried it — the enrollment record
///   does, and a reader injects it back. So the envelope omits the claim
///   rather than guessing at it; a verifier's authority is the signature
///   checking out against that record's own `_apsk`.
///
/// [signingAlgo] names the algorithm of the APKAM keypair the handed
/// `AtKeys` carries, and therefore how the envelope is signed: `rsa2048`
/// (the default, today's OTP flow) or `mldsa65` for a self-retrofit, whose
/// freshly minted ML-DSA keypair rides the same flat fields as base64 of
/// the raw keys.
///
/// [keyEstablishmentAlgo] is the KEM the enrollment's encapsulation key is
/// minted under — pass `AtClientPreference.keyEstablishmentAlgo`. It is an
/// explicit parameter rather than something read from a preference because
/// this function has no client and cannot have one: it runs before the
/// enrollment exists. **Treat it as decided at this call.** The key package
/// rides `enroll:request`, and the only later route into `metadata.keyPackage`
/// is the enrollment's own self-only `enroll:update`, which no client sends
/// yet — so in practice this decides the enrollment's KEM, and changing the
/// preference later takes effect on a new enrollment.
///
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
    final String? materialAlgo =
        SecretSharingAlgos.materialAlgoFor(keyEstablishmentAlgo);
    if (kem == null || materialAlgo == null) {
      throw StateError(
          'enrollmentKeyPackageBuilder: no implementation for '
          '"$keyEstablishmentAlgo". This is the only moment an enrollment\'s '
          'encapsulation target can be set without the enrollment itself later '
          'sending enroll:update, so it fails rather than quietly minting '
          'something else. '
          'Supported: ${SecretSharingAlgos.keyAlgos}');
    }

    // The SEED is what is filed, not the secret key. They are the same 32
    // bytes for X-Wing, but ML-KEM's secret key is an expanded decapsulation
    // key that nothing turns back into a public half — a keyfile holding one
    // could never recover the package it was filed for.
    final Uint8List seed = kem.newSeed();
    final pair = await kem.keyPairFromSeed(seed);
    final String pub = base64Encode(pair.publicKey);
    final String kpid = PackageKey.computeKid(pub);
    final DateTime now = createdAt ?? DateTime.now().toUtc();

    // Both halves share the kpid as their keyId, which is what ties the
    // private half back to the package a sender sealed to.
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.publicEncapsulation,
      keyAlgorithmType: materialAlgo,
      bytes: AtBytes(pair.publicKey),
      createdAt: now,
    ));
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.privateDecapsulation,
      keyAlgorithmType: materialAlgo,
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
      // toJson, not the envelope itself: this map is `EnrollParams.metadata`,
      // which is JSON-encoded onto the wire and read back as a Map by every
      // consumer. A Dart object here survives `jsonEncode` only because its
      // default encodable calls `toJson` for you, and reaches every in-process
      // reader as something they cannot index.
      'keyPackage': signEnvelope(
        payload,
        // One key: this signs a package for an enrollment that does not exist
        // yet, so the only keypair in play is the one just minted for it.
        //
        // ⚠️ **Whichever key `_apsk` will advertise must be the one that signs
        // here.** A peer verifies this package against that record before
        // sealing any secret to the enrollment, so the two disagreeing means
        // the enrollment is created and then receives nothing. Once the
        // enrollment owns a signing key, that is the key on both sides: it is
        // what signs what the enrollment attests to, and a key package is
        // exactly such an attestation. The APKAM key signs here only while
        // the enrollment has no signing key of its own, which is also the only
        // time `_apsk` names it.
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
