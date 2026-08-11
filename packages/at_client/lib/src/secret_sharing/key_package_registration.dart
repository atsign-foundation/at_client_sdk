import 'dart:convert' show base64Decode, base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart' show AtKemAlgorithm;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:meta/meta.dart' show experimental, protected;

/// This APKAM keypair's enc keypair, persisted (by an app callback) across
/// restarts. [encSeed] is the base64 of the KEM's secret **seed**; the public
/// key and the decapsulation key both re-derive from it deterministically.
///
/// The seed rather than the secret key, because the two are only the same
/// thing for X-Wing. ML-KEM's secret key is an expanded decapsulation key that
/// no seeded call reproduces, so a keyfile holding one could never recover the
/// public half — see `AtKemAlgorithm.keyPairFromSeed`.
///
/// [keyAlgo] says which KEM the seed belongs to, and it must be stored
/// alongside it: 32 bytes and 64 bytes are both valid seeds for *some* backend,
/// so the bytes alone do not identify one, and expanding a seed under the wrong
/// KEM yields a key whose kpid nobody is writing to.
///
/// This is the per-APKAM recipient keypair: it belongs to the APKAM keypair
/// (one per keyfile), so a copied keyfile shares it — a copy is the same
/// recipient identity, which is the intended per-APKAM granularity.
@experimental
class PersistedApkamKeys {
  final String encSeed;

  /// An id from [SecretSharingAlgos.keyAlgos]. Defaults to the hybrid, which
  /// is what every seed written before this field existed was.
  final String keyAlgo;

  PersistedApkamKeys({
    required this.encSeed,
    this.keyAlgo = SecretSharingAlgos.xWing,
  });
}

/// Maintains this APKAM keypair's [KeyPackage] for same-atSign secret sharing.
///
/// The recipient unit is the **APKAM keypair** (1:1:1 — one enrollment, one
/// APKAM keypair, one key package): this client holds one KEM enc keypair
/// (its [kpid] is the SHA-256 prefix of the public key) and publishes its APKAM
/// signing key so peers can verify the envelopes it sends. Its key package is
/// conveyed into the enrollment record by riding `enroll:request` as opaque
/// `EnrollParams.metadata` at enrollment time, and amendable afterwards only
/// by the enrollment itself via the self-only `enroll:update`; peers discover
/// it via the gated `enroll:listns` verb.
///
/// By default the enc keypair is generated fresh and held in memory; apps that
/// want it stable across restarts supply [loadApkamKeys] / [saveApkamKeys]
/// (which persist it to the keyfile/keychain alongside the APKAM keypair).
@experimental
mixin KeyPackageRegistration on ApkamSigning, EnvelopeSigning {
  /// Supply to give this APKAM keypair a stable enc keypair across restarts.
  /// Called once, before generating a fresh one; return null to generate fresh.
  Future<PersistedApkamKeys?> Function()? loadApkamKeys;

  /// Supply to persist a freshly generated enc keypair (e.g. to the keyfile /
  /// platform keystore — the app's concern).
  Future<void> Function(PersistedApkamKeys keys)? saveApkamKeys;

  Uint8List? _encSeed;
  Uint8List? _encPublicKey;
  String? _encKeyAlgo;
  bool _registered = false;
  EnrollmentDirectory? _directory;

  /// The atServer-backed key-package directory. Defaults to a verb-backed
  /// implementation; tests assign a fake.
  EnrollmentDirectory get directory =>
      _directory ??= VerbEnrollmentDirectory(atClient);

  set directory(EnrollmentDirectory value) => _directory = value;

  bool get isRegistered => _registered;

  /// This APKAM keypair's encapsulation public key (raw bytes). Throws
  /// [StateError] until [register] has completed.
  Uint8List get encPublicKey {
    if (_encPublicKey == null) {
      throw StateError('register() has not been called');
    }
    return _encPublicKey!;
  }

  /// The **decapsulation key** for [encPublicKey] — for opening by composing
  /// mixins, not for application use.
  ///
  /// Not the seed: this is what `pqOpen` takes, and for ML-KEM the two differ.
  /// It is derived from the persisted seed at [register] time so a caller never
  /// has to know which.
  @protected
  Uint8List get encSecretKey {
    if (_encSecretKey == null) {
      throw StateError('register() has not been called');
    }
    return _encSecretKey!;
  }

  Uint8List? _encSecretKey;

  /// Which KEM [encPublicKey] belongs to — an id from
  /// [SecretSharingAlgos.keyAlgos]. Throws [StateError] until [register]
  /// completes.
  String get encKeyAlgo {
    if (_encKeyAlgo == null) {
      throw StateError('register() has not been called');
    }
    return _encKeyAlgo!;
  }

  /// The KEM this client would mint a *fresh* key under, per
  /// [AtClientPreference.keyEstablishmentAlgo].
  ///
  /// Not necessarily [encKeyAlgo]: a client that loaded an existing key keeps
  /// that key's algorithm, because its kpid is the address its enrollment
  /// already advertised.
  String get configuredKeyAlgo =>
      atClient.getPreferences()?.keyEstablishmentAlgo ??
      SecretSharingAlgos.xWing;

  /// This key package's addressing id ([KeyPackage.kpid]) — the SHA-256 prefix
  /// of the encapsulation public key. Throws [StateError] until [register]
  /// completes.
  String get kpid => PackageKey.computeKid(base64Encode(encPublicKey));

  /// This APKAM keypair's key package (the one registered for discovery).
  /// Throws [StateError] until [register] has generated the enc keypair.
  ///
  /// `suites` is derived from the advertised key rather than stated, so it can
  /// never claim a construction this holder's own key cannot decapsulate.
  KeyPackage get myKeyPackage => KeyPackage(
        enrollmentId: enrollmentId,
        createdAt: DateTime.now().toUtc(),
        keys: [
          PackageKey(
            use: SecretSharingAlgos.useEnc,
            alg: encKeyAlgo,
            pub: base64Encode(encPublicKey),
          ),
        ],
      );

  /// This key package wrapped in an APKAM-signed envelope — the value to store
  /// at `metadata.keyPackage` when the package rides `enroll:request`.
  ///
  /// A key package *is* an encapsulation target: whoever's enc public key
  /// ends up here is who the atSign's other clients seal their secrets to. So
  /// it is advertised signed, and [VerbEnrollmentDirectory] verifies the
  /// signature against this enrollment's `_apsk` before treating the key as
  /// this enrollment's. Without that, the target is only as trustworthy as
  /// whatever served the enrollment record.
  ///
  /// Throws [StateError] until [register] has generated the enc keypair.
  Future<Map<String, Object?>> signedKeyPackagePayload() async =>
      await wrapAndSign(myKeyPackage.toJson());

  /// Generates (or loads, via [loadApkamKeys]) this APKAM keypair's KEM enc
  /// keypair and publishes its APKAM signing key (so peers can verify its
  /// envelopes), then returns this client's [KeyPackage]. Idempotent.
  ///
  /// The returned key package is conveyed into the enrollment record by riding
  /// `enroll:request` as opaque `EnrollParams.metadata` at enrollment time — no
  /// directory call writes it, and the only later route into the record is the
  /// enrollment's own `enroll:update`. Peers then discover it via the gated
  /// `enroll:listns` verb.
  Future<KeyPackage> register() async {
    if (_encSeed == null) {
      final loaded = await loadApkamKeys?.call();

      // A loaded key keeps its OWN algorithm, whatever the preference now
      // says. Its kpid is the address this enrollment already advertised, and
      // re-minting under a different KEM would move that address to one nobody
      // is writing to — the client would scan for envelopes that are being
      // sent somewhere else. Changing the preference therefore takes effect on
      // the next enrollment, not on this one.
      final String algo = loaded?.keyAlgo ?? configuredKeyAlgo;
      if (loaded != null && loaded.keyAlgo != configuredKeyAlgo) {
        logger.info(
            'This enrollment holds a ${loaded.keyAlgo} key package and the '
            'preference asks for $configuredKeyAlgo. Keeping the '
            '${loaded.keyAlgo} one: '
            'the kpid is the address peers already seal to. A new enrollment '
            'will mint $configuredKeyAlgo.');
      }

      final AtKemAlgorithm? kem = SecretSharingAlgos.kemFor(algo);
      if (kem == null) {
        throw StateError(
            'No key-establishment implementation for "$algo" — this client '
            'cannot mint or recover a key package. Supported: '
            '${SecretSharingAlgos.keyAlgos}');
      }

      // The SEED is what is persisted and what everything re-derives from.
      // Storing the secret key instead is correct only for X-Wing, whose
      // secret key IS its seed; ML-KEM's is an expanded decapsulation key that
      // nothing turns back into a public half.
      _encSeed = loaded != null ? base64Decode(loaded.encSeed) : kem.newSeed();
      final kp = await kem.keyPairFromSeed(_encSeed!);
      _encPublicKey = kp.publicKey;
      _encSecretKey = kp.secretKey;
      _encKeyAlgo = algo;

      if (loaded == null) {
        await saveApkamKeys?.call(PersistedApkamKeys(
            encSeed: base64Encode(_encSeed!), keyAlgo: algo));
      }
    }
    await publishPublicSigningKey();
    _registered = true;
    logger.info('Prepared $encKeyAlgo key package for enrollment '
        '$enrollmentId (kpid $kpid)');
    return myKeyPackage;
  }
}
