import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        CryptographicMaterialAlgorithm,
        CryptographicMaterial,
        CryptographicMaterialRole,
        KeyEntryStatus,
        CryptographicMaterialStatus,
        WrittenAtKeysIo;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/enroll/enrollment_update_request.dart';
import 'package:at_client/src/enroll/enrollment_updater.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, signEnvelope;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_utils/at_utils.dart' show AtSignLogger, AtUtils;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// Brings an enrollment's advertised key package into line with
/// [AtClientPreference.keyEstablishmentAlgorithms] — minting an encapsulation
/// keypair for every algorithm the list names and the enrollment does not
/// hold, retiring every one it holds that the list no longer names, and
/// republishing the package by `enroll:update`.
///
/// **A key package is amended, never replaced.** The advertisement this
/// publishes carries every key the enrollment holds — minted, kept and retired
/// alike — because the write rewrites `metadata.keyPackage` whole, so anything
/// left out is withdrawn from the advertisement. A retired key stays
/// advertised *as retired*, so nothing new is sealed to it while a peer
/// holding an envelope still in flight can see whose key it was.
///
/// ⚠️ **File first, then publish.** Publishing an encapsulation key before
/// filing its private half lets every sender that reads the advertisement in
/// that window seal data to a key **nobody holds** — durable writes that no
/// later repair opens, because the decapsulation key never existed. Filing
/// first costs nothing: no sender can address the key until it is advertised,
/// and the next start publishes it.
///
/// **Inert unless something changed.** An enrollment created under the current
/// list already holds every algorithm it names and finds nothing to do.
@experimental
class KeyPackageMinting with ApkamSigning {
  KeyPackageMinting(this.atClient, {EnrollmentUpdater? updater})
      : _updater = updater ?? EnrollmentUpdater();

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('KeyPackageMinting');

  final EnrollmentUpdater _updater;

  /// Mints, files and advertises an encapsulation keypair for every algorithm
  /// the configured list names and this enrollment lacks; retires every one it
  /// holds that the list no longer names. Returns both, each empty when there
  /// was nothing to do.
  ///
  /// **The enrollment always ends holding at least one active key**: the
  /// configured list is never empty, and any algorithm in it is either absent
  /// (so a key is minted for it) or already active (so that key is not among
  /// the superseded).
  Future<({List<String> minted, List<String> retired})>
      reconcileKeyPackage() async {
    const nothing = (minted: <String>[], retired: <String>[]);

    final wanted =
        atClient.getPreferences()?.keyEstablishmentAlgorithms ?? const [];
    if (wanted.isEmpty) return nothing;

    final atSign = atClient.getCurrentAtSign();
    final io = atClient.atKeysIo;
    if (atSign == null || io == null) return nothing;
    if (io is! WrittenAtKeysIo) {
      logger.warning('Not reconciling the key package for $atSign: this '
          'AtKeysIo cannot persist, so a minted key would be advertised and '
          'then lost at the next start, leaving peers sealing to an address '
          'nothing can open');
      return nothing;
    }

    final atLookUp = atClient.getRemoteSecondary()?.atLookUp;
    final enrolment = atClient.enrollmentId;
    if (enrolment == null || isAtSignCredential(enrolment)) {
      logger.info('Not reconciling the key package for $atSign: the atSign\'s '
          'own credential has no enrollment record to amend');
      return nothing;
    }

    final AtKeys keys = await io.read(atSign);
    final advertised = advertisedKeysIn(keys, enrolment);
    final held = advertised.keys;
    final active = [
      for (final key in held)
        if (key.offeredForNewOperations) key
    ];

    final missing = [
      for (final algorithm in wanted)
        if (!active.any((key) => key.alg == algorithm)) algorithm
    ];
    final superseded = [
      for (final key in active)
        if (!wanted.contains(key.alg)) key
    ];
    if (missing.isEmpty && superseded.isEmpty) return nothing;

    // NOTE: the mint runs before the write, so a mint that throws leaves the
    // keyfile and the advertisement exactly as they were.
    final minted = [for (final algorithm in missing) await _mint(algorithm)];

    // NOTE: one atomic keyfile update for the whole change, never a
    // hand-rolled read → mutate → write: a concurrent start files conveyed key
    // material through this same keyfile, and whichever flushed second would
    // drop the other's addition.
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      for (final key in minted) {
        keys.addKey(CryptographicMaterial(
          enrollmentId: enrolment,
          keyId: key.kpid,
          role: CryptographicMaterialRole.publicEncapsulation,
          algorithm: key.materialAlgo,
          bytes: AtBytes(key.publicKey),
          createdAt: key.createdAt,
        ));
        keys.addKey(CryptographicMaterial(
          enrollmentId: enrolment,
          keyId: key.kpid,
          role: CryptographicMaterialRole.privateDecapsulation,
          algorithm: key.materialAlgo,
          // NOTE: the SEED, not the decapsulation key — the same bytes for
          // X-Wing but not for ML-KEM, whose decapsulation key is expanded.
          bytes: AtBytes(key.seed),
          createdAt: key.createdAt,
        ));
      }
      // NOTE: the kid IS the keyfile's keyId for this material — both are
      // PackageKey.computeKid over the same public bytes, which is what ties
      // the two halves to the package a sender sealed to.
      for (final key in superseded) {
        if (advertised.tagged) {
          keys.retireKey(enrolment, key.kid);
        } else {
          // NOTE: untagged material lives in the atSign's container, and
          // retireKey looks only in the enrollment's — it would silently find
          // nothing, leaving the key active in the keyfile while the
          // advertisement below called it retired.
          keys.retireAtSignKey(key.kid);
        }
      }
      return true;
    });

    // NOTE: published only after the filing, so no advertisement ever names a
    // key whose private half this client does not already hold.
    await _publish(
      enrolment,
      atLookUp!,
      [
        for (final key in minted)
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc, alg: key.alg, pub: key.publicKey),
        for (final key in held)
          if (!superseded.contains(key))
            key
          else
            PackageKey(
                kid: key.kid,
                use: key.use,
                alg: key.alg,
                pub: key.pub,
                status: KeyEntryStatus.retired),
      ],
    );

    if (missing.isNotEmpty) {
      logger.info('Minted and advertised ${missing.join(', ')} '
          'encapsulation key(s) for $enrolment');
    }
    if (superseded.isNotEmpty) {
      logger.info('Retired ${superseded.map((k) => k.alg).join(', ')} '
          'encapsulation key(s) for $enrolment: the configured list no longer '
          'names them. They stay advertised as retired, so what was already '
          'sealed to them still opens');
    }
    return (minted: missing, retired: [for (final key in superseded) key.alg]);
  }

  /// Every encapsulation key [enrolment] advertises in [keys] — active and
  /// retired, in that order — as the entries a key package carries.
  ///
  /// Read back from the keyfile rather than from the package being replaced:
  /// an entry in the old advertisement whose private half is not here is an
  /// address nothing opens, and republishing it would keep senders aiming at
  /// it.
  ///
  /// Material whose algorithm this build does not implement is skipped, and
  /// [CryptographicMaterialStatus.dead] material is left out entirely.
  ///
  /// ⚠️ **Tagged material wins and untagged material is the FALLBACK.** An
  /// enrollment's first key package is filed with no enrollment id, before the
  /// atServer has assigned one, so the ordinary state of a freshly created
  /// enrollment is one *untagged* pair; a reader that took only tagged
  /// material would see an enrollment holding nothing and mint a duplicate key
  /// under the same algorithm.
  ///
  /// The two sets never mix: merging them would let this enrollment advertise
  /// a key another enrollment's record was built on.
  @visibleForTesting
  static ({List<PackageKey> keys, bool tagged}) advertisedKeysIn(
      AtKeys keys, String enrolment) {
    List<PackageKey> gather({required bool tagged}) {
      final entries = <PackageKey>[];
      for (final material in keys.keys) {
        final owned = tagged
            ? material.enrollmentId == enrolment
            : material.enrollmentId == null;
        if (!owned) continue;
        if (material.role != CryptographicMaterialRole.publicEncapsulation) {
          continue;
        }
        if (material.status == CryptographicMaterialStatus.dead) continue;
        final alg = SecretSharingAlgos.keyAlgoForMaterial(material.algorithm);
        if (alg == null) continue;
        entries.add(PackageKey.fromBytes(
          use: SecretSharingAlgos.useEnc,
          alg: alg,
          pub: Uint8List.fromList(material.bytes.bytes),
          // NOTE: the keyfile's own token, carried across rather than
          // collapsed to one of the two this build knows — a third value
          // written by a newer client says something narrower about the key,
          // and rewriting it would republish the record with that weakened.
          status: KeyEntryStatus.of(material.status),
        ));
      }
      entries.sort((a, b) {
        if (a.offeredForNewOperations != b.offeredForNewOperations) {
          return a.offeredForNewOperations ? -1 : 1;
        }
        return 0;
      });
      return entries;
    }

    final own = gather(tagged: true);
    // NOTE: `tagged` is reported because it decides which verb retires from
    // the set — `retireKey` on the wrong container silently does nothing.
    return own.isNotEmpty
        ? (keys: own, tagged: true)
        : (keys: gather(tagged: false), tagged: false);
  }

  /// Signs the amended package and sends it as the enrollment's own
  /// `enroll:update`.
  ///
  /// ⚠️ **Whichever key `_apsk` advertises must be the one that signs here.** A
  /// peer verifies this package against that record before sealing anything to
  /// the enrollment, so the two disagreeing leaves the enrollment advertising a
  /// package nobody will act on; the keys come from [ApkamSigning.signingKeys],
  /// which is what composes `_apsk`.
  ///
  /// Only `metadata` is named: the atServer merges it per key, so a sibling
  /// entry survives a write from this one, and the verb refuses `namespaces`
  /// and the approval state outright, so a key package amendment cannot widen
  /// the enrollment's own grant.
  Future<void> _publish(
      String enrolment, AtLookUp atLookUp, List<PackageKey> keys) async {
    final payload = KeyPackage.payloadFor(
      createdAt: DateTime.now().toUtc(),
      keys: keys,
    );
    await _updater.update(
        EnrollmentUpdateRequest(
          enrollmentId: enrolment,
          metadata: {
            // NOTE: toJson, not the envelope object — EnrollParams.metadata is
            // JSON-encoded onto the wire and read back as a Map.
            'keyPackage': signEnvelope(
              payload,
              type: EnvelopeType.keyPackage,
              keys: await signingKeys,
            ).toJson(),
          },
        ),
        atLookUp);
  }

  Future<_MintedEncKey> _mint(String algorithm) async {
    final kem = SecretSharingAlgos.kemFor(algorithm);
    final materialAlgo = SecretSharingAlgos.materialAlgoFor(algorithm);
    if (kem == null || materialAlgo == null) {
      // NOTE: unreachable — AtClientPreference refuses a list naming an
      // algorithm this build cannot mint.
      throw ArgumentError.value(
          algorithm,
          'algorithm',
          'no key-establishment implementation, though the preference '
              'accepted it. Supported: ${SecretSharingAlgos.keyAlgos}');
    }
    final Uint8List seed = kem.newSeed();
    final pair = await kem.keyPairFromSeed(seed);
    return _MintedEncKey(
      alg: algorithm,
      materialAlgo: materialAlgo,
      seed: seed,
      publicKey: pair.publicKey,
      kpid: PackageKey.computeKid(base64Encode(pair.publicKey)),
      createdAt: DateTime.now().toUtc(),
    );
  }
}

/// A freshly minted encapsulation keypair, before it is filed or advertised.
class _MintedEncKey {
  final String alg;

  /// The keyfile's spelling of [alg].
  final CryptographicMaterialAlgorithm materialAlgo;

  final Uint8List seed;
  final Uint8List publicKey;
  final String kpid;
  final DateTime createdAt;

  _MintedEncKey({
    required this.alg,
    required this.materialAlgo,
    required this.seed,
    required this.publicKey,
    required this.kpid,
    required this.createdAt,
  });
}
