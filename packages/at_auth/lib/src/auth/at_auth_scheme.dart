import 'package:at_auth/src/enroll/apkam_key_conveyance.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/serialization/key_ids.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:meta/meta.dart';

/// Builds the [AtLookUp] an authentication runs over.
///
/// Injected at `AtAuth.create` / `AtEnrollment.create` time to take over
/// construction; when none is injected the default is
/// [AtAuthScheme.lookUpFactory].
///
/// [keys] is null for the CRAM-only connection an activation starts on, before
/// any key material exists.
///
/// The connection returned belongs to whoever called the factory: at_auth closes
/// it when the operation that asked for it fails or finishes with it. Do not
/// hand back a connection the caller still needs.
typedef AtLookUpFactory = AtLookUp Function(
  Atsign atsign,
  AtRootDomain rootDomain,
  AtKeys? keys, {
  String? enrollmentId,
});

/// The authentication scheme at_auth uses, chosen by the caller at
/// `AtAuth.create` / `AtEnrollment.create` time.
///
/// It is deliberately **not** inferred from the key material. A keyset minted by
/// [AtKeys.generate] carries both a classical and a post-quantum APKAM key, so
/// key material cannot express which one an atServer expects — that is a
/// property of the deployment, and the application (at_client) owns it.
sealed class AtAuthScheme {
  const AtAuthScheme._();

  /// RSA-2048/SHA-256, signed with the legacy `apkamPrivateKey`. What every
  /// atServer verifies today.
  static const AtAuthScheme legacy = _LegacyAtAuthScheme._();

  @experimental
  static const AtAuthScheme postQuantum = _PostQuantumAtAuthScheme._();

  /// The [AtLookUpFactory] used when a caller injects none — every connection
  /// built signs with this scheme and the matching key from the keys it is
  /// given.
  AtLookUpFactory get lookUpFactory =>
      (atsign, rootDomain, keys, {enrollmentId}) => buildAtLookUp(
            this,
            atsign,
            rootDomain,
            keys,
            enrollmentId: enrollmentId,
          );

  ApkamKeyConveyance get conveyance;

  /// The at_chops algorithm this scheme signs PKAM with — the single source for
  /// the keypair [mintKeys] generates, the [signingAlgo] the enroll and
  /// pkam verbs are stamped with, and the `keyAlgorithmType` the minted material
  /// records.
  AtSignatureAlgorithm get signatureAlgorithm;

  /// How this scheme names itself on the wire — `rsa2048` or `mldsa65`. The
  /// same token the enroll verb's `signingAlgo` carries and an [AtKeysMaterial]
  /// records as its `keyAlgorithmType`, so an enrollment record and the key
  /// material it was minted from cannot disagree.
  String get signingAlgo => signatureAlgorithm.signingAlgoType.name;

  /// The APKAM public key this scheme enrolls, from where that scheme keeps it:
  /// the legacy flat field, or the [KeyIds.apkamPQ] verification material.
  ///
  /// This is what goes on the enroll verb, so it must be the counterpart of
  /// [requireApkamPrivateKey] — the atServer verifies with this key the
  /// signature PKAM makes with that one.
  AtBytes requireApkamPublicKey(AtKeys keys);

  /// The APKAM private key this scheme signs PKAM with — see
  /// [requireApkamPublicKey] for the half the atServer holds.
  ///
  /// Never falls back to the other scheme's key: that would authenticate as an
  /// identity the caller did not ask for.
  AtBytes requireApkamPrivateKey(AtKeys keys);

  AtAuthenticationException _missingApkamKey(
          AtKeys keys, String name, String half) =>
      AtAuthenticationException(
          'The keys for ${keys.atsign} carry no $name APKAM $half key');

  /// Mints a fresh APKAM keypair for this scheme and writes it into [keys], in
  /// the place [buildAtLookUp] reads it back from.
  ///
  /// Only the APKAM material: nothing else in [keys] is touched, so this can
  /// complete a keyset that already carries its encryption material.
  ///
  /// The post-quantum arm delegates to [AtKeys.generatePQEnrollmentPackage],
  /// which mints the APKAM scheme key plus the enrollment-scoped X-Wing
  /// keypackage material.
  Future<void> mintKeys(AtKeys keys);

  @internal
  String get publishedPublicKeyName;

  @internal
  bool get storesPublishedPublicKey;
}

final class _LegacyAtAuthScheme extends AtAuthScheme {
  const _LegacyAtAuthScheme._() : super._();

  @override
  ApkamKeyConveyance get conveyance => const RsaKeyConveyance();

  @override
  AtSignatureAlgorithm get signatureAlgorithm => RsaSigningAlgo();

  @override
  AtBytes requireApkamPublicKey(AtKeys keys) {
    // ignore: deprecated_member_use_from_same_package
    return keys.apkamPublicKey ??
        (throw _missingApkamKey(keys, 'legacy', 'public'));
  }

  @override
  AtBytes requireApkamPrivateKey(AtKeys keys) {
    // ignore: deprecated_member_use_from_same_package
    return keys.apkamPrivateKey ??
        (throw _missingApkamKey(keys, 'legacy', 'private'));
  }

  @override
  Future<void> mintKeys(AtKeys keys) async {
    final keyPair = await signatureAlgorithm.generateKeyPair();
    // ignore: deprecated_member_use_from_same_package
    keys.apkamPublicKey = AtBytes(keyPair.publicKey);
    // ignore: deprecated_member_use_from_same_package
    keys.apkamPrivateKey = AtBytes(keyPair.secretKey);
  }

  @override
  String get publishedPublicKeyName => KeyIds.publishedLegacyPublicKey;

  @override
  bool get storesPublishedPublicKey => true;
}

final class _PostQuantumAtAuthScheme extends AtAuthScheme {
  const _PostQuantumAtAuthScheme._() : super._();

  @override
  ApkamKeyConveyance get conveyance => XWingKeyConveyance();

  @override
  AtSignatureAlgorithm get signatureAlgorithm => MlDsa65PureDartAlgo();

  @override
  AtBytes requireApkamPublicKey(AtKeys keys) {
    return _pqApkamKey(keys, CryptographicKeyType.publicVerification) ??
        (throw _missingApkamKey(keys, 'pq', 'public'));
  }

  @override
  AtBytes requireApkamPrivateKey(AtKeys keys) {
    return _pqApkamKey(keys, CryptographicKeyType.privateSigning) ??
        (throw _missingApkamKey(keys, 'pq', 'private'));
  }

  @override
  Future<void> mintKeys(AtKeys keys) async {
    for (final material in await AtKeys.generatePQEnrollmentPackage(
      keys.atsign,
      keys.enrollmentId,
    )) {
      keys.addKey(material);
    }
  }

  @override
  String get publishedPublicKeyName => KeyIds.publishedPqPublicKey;

  @override
  bool get storesPublishedPublicKey => false;

  AtBytes? _pqApkamKey(AtKeys keys, String keyPartType) {
    final material = keys.getKey(KeyIds.apkamPQ, keyPartType);
    return material == null ? null : AtBytes(material.bytes);
  }
}

/// Builds the [AtLookUp] an authentication runs over, using [scheme]
/// and the matching key from [keys].
///
/// at_lookup binds its PKAM key and scheme algorithm at construction and keeps
/// them immutable, so the connection cannot be built until the keys are in
/// hand. That is why authentication owns this step: it reads (or mints) the keys
/// first, then builds the connection that can sign with them.
///
/// [keys] is null for the CRAM-only connection an activation starts on, before
/// any key material exists.
///
/// Throws [AtAuthenticationException] when [keys] carries no APKAM private key
/// for [scheme] — a keyset that cannot authenticate the way it was asked to.
AtLookUp buildAtLookUp(
  AtAuthScheme scheme,
  Atsign atsign,
  AtRootDomain rootDomain,
  AtKeys? keys, {
  String? enrollmentId,
}) {
  final pkamPrivateKey =
      keys == null ? null : scheme.requireApkamPrivateKey(keys).bytes;

  return AtLookUp.create(
    atsign,
    rootDomain.rootDomain,
    rootDomain.rootPort,
    signingAlgo: scheme.signatureAlgorithm,
    pkamPrivateKey: pkamPrivateKey,
    enrollmentId: enrollmentId,
  );
}
