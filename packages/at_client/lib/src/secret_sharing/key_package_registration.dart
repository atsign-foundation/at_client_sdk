import 'dart:convert' show base64Decode, base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart' show XWingPureDartAlgo;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:meta/meta.dart' show experimental, protected;

/// This APKAM keypair's X-Wing enc keypair, persisted (by an app callback)
/// across restarts. [xWingSeed] is the base64 of the 32-byte X-Wing secret
/// seed; the public key re-derives from it deterministically.
///
/// This is the per-APKAM recipient keypair: it belongs to the APKAM keypair
/// (one per keyfile), so a copied keyfile shares it — a copy is the same
/// recipient identity, which is the intended per-APKAM granularity.
@experimental
class PersistedApkamKeys {
  final String xWingSeed;

  PersistedApkamKeys({required this.xWingSeed});
}

/// Maintains this APKAM keypair's [KeyPackage] for same-atSign secret sharing.
///
/// The recipient unit is the **APKAM keypair**: this client holds one X-Wing
/// enc keypair (its [kpid] is the SHA-256 prefix of the public key), registers
/// it via the [EnrollmentDirectory] into its enrollment record, and publishes
/// its APKAM signing key so peers can verify the envelopes it sends. Key
/// packages are enrollment-internal — never published, discovered only via the
/// gated `enroll:listfornamespace` verb.
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

  Uint8List? _xWingSeed;
  Uint8List? _xWingPublicKey;
  bool _registered = false;
  EnrollmentDirectory? _directory;

  /// The atServer-backed key-package directory. Defaults to a verb-backed
  /// implementation; tests assign a fake.
  EnrollmentDirectory get directory =>
      _directory ??= VerbEnrollmentDirectory(atClient);

  set directory(EnrollmentDirectory value) => _directory = value;

  bool get isRegistered => _registered;

  /// This APKAM keypair's X-Wing public key (raw bytes). Throws [StateError]
  /// until [register] has completed.
  Uint8List get xWingPublicKey {
    if (_xWingPublicKey == null) {
      throw StateError('register() has not been called');
    }
    return _xWingPublicKey!;
  }

  /// This APKAM keypair's X-Wing secret seed — for decapsulation by composing
  /// mixins, not for application use.
  @protected
  Uint8List get xWingSeed {
    if (_xWingSeed == null) {
      throw StateError('register() has not been called');
    }
    return _xWingSeed!;
  }

  /// This key package's addressing id ([KeyPackage.kpid]) — the SHA-256 prefix
  /// of the X-Wing public key. Throws [StateError] until [register] completes.
  String get kpid => PackageKey.computeKid(base64Encode(xWingPublicKey));

  /// This APKAM keypair's key package (the one registered for discovery).
  /// Throws [StateError] until [register] has generated the enc keypair.
  KeyPackage get myKeyPackage => KeyPackage(
        enrollmentId: enrollmentId,
        createdAt: DateTime.now().toUtc(),
        keys: [
          PackageKey(
            use: SecretSharingAlgos.useEnc,
            alg: SecretSharingAlgos.xWing,
            pub: base64Encode(xWingPublicKey),
          ),
        ],
      );

  /// Generates (or loads, via [loadApkamKeys]) this APKAM keypair's X-Wing enc
  /// keypair, publishes its APKAM signing key (so peers can verify its
  /// envelopes), and registers its key package in the enrollment record so
  /// peers can discover it. Idempotent.
  Future<KeyPackage> register() async {
    if (_xWingSeed == null) {
      final loaded = await loadApkamKeys?.call();
      if (loaded != null) {
        _xWingSeed = base64Decode(loaded.xWingSeed);
        // the public key derives deterministically from the seed
        final kp = await XWingPureDartAlgo.instance.generateKeyPair(_xWingSeed);
        _xWingPublicKey = kp.publicKey;
      } else {
        final kp = await XWingPureDartAlgo.instance.generateKeyPair();
        _xWingSeed = kp.secretKey;
        _xWingPublicKey = kp.publicKey;
        await saveApkamKeys
            ?.call(PersistedApkamKeys(xWingSeed: base64Encode(_xWingSeed!)));
      }
    }
    await publishPublicSigningKey();
    final keyPackage = myKeyPackage;
    await directory.registerKeyPackage(keyPackage);
    _registered = true;
    logger.info('Registered key package for enrollment $enrollmentId '
        '(kpid $kpid)');
    return keyPackage;
  }
}
