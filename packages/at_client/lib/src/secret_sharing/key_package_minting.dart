import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        AtKeys,
        AtKeysMaterial,
        CryptographicKeyType,
        EnrollmentUpdateRequest,
        KeyEntryStatus,
        KeyPartStatus,
        WrittenAtKeysIo;
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
/// This is the **writer** the multi-key receiver has been waiting for. The
/// reader half shipped first, deliberately: `keyPackageMaterials` returns every
/// held material, `EnvelopeAddressing.regexForAny` watches every address, and
/// `pqOpen` takes the secret selected by `envelope.kid`. Until this class
/// existed a package could never gain a key, so all of that answered at exactly
/// one address and the plural machinery was untestable against a real second
/// key.
///
/// **A key package is amended, never replaced.** The advertisement this
/// publishes carries every key the enrollment holds — the ones it just minted,
/// the ones it is keeping, and the ones it has retired — because the write
/// rewrites `metadata.keyPackage` whole, so anything left out is withdrawn. A
/// retired key stays advertised *as retired*: `KeyPackage.bestKeyFor` skips it
/// so nothing new is sealed to it, while a peer holding an envelope still in
/// flight can see whose key it was. Dropping the entry instead would strand
/// that envelope with nothing to name.
///
/// ⚠️ **File first, then publish — the OPPOSITE order to
/// `SigningKeyMinting`, and the asymmetry is the whole point.** Both classes
/// mint a key, advertise it and file it, and each picks the order whose
/// failure it can live with:
///
/// - Publish an encapsulation key before filing its private half and every
///   sender that reads the advertisement in that window seals data to a key
///   **nobody holds**. Those writes are stored and durable; no later repair
///   opens them, because the decapsulation key never existed. That is data
///   loss.
/// - File it before publishing and the client holds a key nothing has been
///   sealed to yet, which costs nothing: no sender can address it until it is
///   advertised, and the next start publishes it.
///
/// A signing key inverts both arms — publishing early costs nothing, filing
/// early permanently unverifies whatever gets signed in the window — which is
/// why the two classes disagree. `NskeyPrivateFiling` files before publishing
/// for this same reason.
///
/// **Inert unless something changed.** An enrollment created under the current
/// list already holds every algorithm it names and finds nothing to do, which
/// is every start after the first. What reaches the working part of this class
/// is a deployment that has edited the list since the enrollment was created.
@experimental
class KeyPackageMinting with ApkamSigning {
  KeyPackageMinting(this.atClient, {AtEnrollment? enrollment})
      : _enrollment = enrollment ?? AtEnrollment.create();

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('KeyPackageMinting');

  final AtEnrollment _enrollment;

  /// Mints, files and advertises an encapsulation keypair for every algorithm
  /// the configured list names and this enrollment lacks; retires every one it
  /// holds that the list no longer names. Returns both, each empty when there
  /// was nothing to do.
  ///
  /// **The enrollment always ends holding at least one active key**, and that
  /// is a property of the two lists rather than something checked. An
  /// enrollment advertising nothing active would look entirely healthy —
  /// authenticating normally, syncing normally — while silently receiving
  /// nothing anyone sealed to it, so it is worth saying why it cannot happen:
  /// the configured list is never empty, and any algorithm in it is either
  /// absent (so a key is minted for it) or already active (so that key is not
  /// among the superseded). A moving deployment mints before it retires.
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

    // enroll:update is self-only, so there has to BE an enrollment for the
    // atServer to accept the write against. A client running as `primary`
    // holds no enrollment record and its key package lives nowhere this can
    // amend.
    final atLookUp = atClient.getRemoteSecondary()?.atLookUp;
    final enrolment = atLookUp?.enrollmentId;
    if (enrolment == null) {
      logger.info('Not reconciling the key package for $atSign: this client '
          'is not enrolled, so there is no enrollment record whose '
          'metadata.keyPackage it could amend');
      return nothing;
    }

    final AtKeys keys = await io.read(atSign);
    final advertised = advertisedKeysIn(keys, enrolment);
    final held = advertised.keys;
    final active = [
      for (final key in held)
        if (key.status == KeyEntryStatus.active) key
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

    // No guard here against retiring the last active key, because the shape of
    // the two lists above already makes that unreachable and a guard that
    // cannot fire reads as a safeguard while exercising nothing. `wanted` is
    // non-empty (the preference refuses an empty list), so take any algorithm
    // in it: either it is not active, and it is in `missing`, so a key is
    // minted; or it is active, and that key is not in `superseded`, so a key
    // is kept. Either way the enrollment ends with at least one active key.
    // The mint runs before the write, so a mint that throws leaves the keyfile
    // and the advertisement exactly as they were.
    final minted = [for (final algorithm in missing) await _mint(algorithm)];

    // One atomic keyfile update for the whole change, never a hand-rolled
    // read → mutate → write: a client's start files conveyed key material
    // through this same keyfile, and whichever of the two flushed second
    // would drop the other's addition.
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      for (final key in minted) {
        keys.addKey(AtKeysMaterial(
          enrollmentId: enrolment,
          keyId: key.kpid,
          keyPartType: CryptographicKeyType.publicEncapsulation,
          keyAlgorithmType: key.materialAlgo,
          bytes: AtBytes(key.publicKey),
          createdAt: key.createdAt,
        ));
        keys.addKey(AtKeysMaterial(
          enrollmentId: enrolment,
          keyId: key.kpid,
          keyPartType: CryptographicKeyType.privateDecapsulation,
          keyAlgorithmType: key.materialAlgo,
          // The SEED, not the decapsulation key: they are the same bytes for
          // X-Wing and not for ML-KEM, whose decapsulation key is expanded and
          // which no seeded call reproduces from.
          bytes: AtBytes(key.seed),
          createdAt: key.createdAt,
        ));
      }
      // Both halves move to retired; neither is removed. The public one is
      // what the advertisement goes on carrying, and the private one is what
      // still opens everything already sealed to it.
      // The kid IS the keyfile's keyId for this material: both are
      // PackageKey.computeKid over the same public bytes, which is what ties
      // the two halves to the package a sender sealed to.
      for (final key in superseded) {
        if (advertised.tagged) {
          keys.retireKey(enrolment, key.kid);
        } else {
          // Untagged material lives in the atSign's container, not this
          // enrollment's, and retireKey looks only in the latter — it would
          // find nothing and report nothing, leaving the key active in the
          // keyfile while the advertisement below called it retired.
          keys.retireAtSignKey(key.kid);
        }
      }
      return true;
    });

    // Published only after the filing, so no advertisement ever names a key
    // whose private half this client does not already hold.
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
  /// Read back from the keyfile rather than from the package that is being
  /// replaced, because the keyfile is what this client can actually answer
  /// with: an entry in the old advertisement whose private half is not here is
  /// an address nothing opens, and republishing it would keep senders aiming
  /// at it.
  ///
  /// Material whose algorithm this build does not implement is skipped, and
  /// [KeyPartStatus.dead] material is left out entirely — retirement is as
  /// close to deletion as a keyfile gets, and a dead key is not something to
  /// go on advertising.
  ///
  /// ⚠️ **Tagged material wins, and untagged material is the FALLBACK — the
  /// same rule `keyPackageMaterials` encodes, and it is not optional.**
  /// `enrollmentKeyPackageBuilder` files an enrollment's first key package
  /// with **no enrollment id**: it runs before the atServer has assigned one.
  /// So the ordinary state of a freshly created enrollment is one *untagged*
  /// pair, and a reader that took only tagged material would see an enrollment
  /// holding nothing, mint a duplicate key under the same algorithm, and
  /// advertise a package beside the one already in the record.
  ///
  /// The two sets never mix. A retrofitted keyfile carries the legacy
  /// enrollment's untagged package beside this enrollment's tagged one, and
  /// merging them would let this enrollment advertise a key another
  /// enrollment's record was built on.
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
        if (material.keyPartType != CryptographicKeyType.publicEncapsulation) {
          continue;
        }
        if (material.status == KeyPartStatus.dead) continue;
        final alg =
            SecretSharingAlgos.keyAlgoForMaterial(material.keyAlgorithmType);
        if (alg == null) continue;
        entries.add(PackageKey.fromBytes(
          use: SecretSharingAlgos.useEnc,
          alg: alg,
          pub: Uint8List.fromList(material.bytes.bytes),
          status: material.status == KeyPartStatus.active
              ? KeyEntryStatus.active
              : KeyEntryStatus.retired,
        ));
      }
      entries.sort((a, b) {
        if ((a.status == KeyEntryStatus.active) !=
            (b.status == KeyEntryStatus.active)) {
          return a.status == KeyEntryStatus.active ? -1 : 1;
        }
        return 0;
      });
      return entries;
    }

    final own = gather(tagged: true);
    // Which set won decides which verb retires from it: tagged material lives
    // in the enrollment's own container and untagged material in the atSign's,
    // and `retireKey` on the wrong one finds nothing and silently does nothing.
    return own.isNotEmpty
        ? (keys: own, tagged: true)
        : (keys: gather(tagged: false), tagged: false);
  }

  /// Signs the amended package and sends it as the enrollment's own
  /// `enroll:update`.
  ///
  /// ⚠️ **Whichever key `_apsk` advertises must be the one that signs here** —
  /// the same rule `enrollmentKeyPackageBuilder` states, for the same reason. A
  /// peer verifies this package against that record before sealing anything to
  /// the enrollment, so the two disagreeing means the enrollment goes on
  /// advertising a package nobody will act on. [ApkamSigning.signingKeys] is
  /// what composes `_apsk`, so taking the keys from there is what keeps them
  /// the same set rather than two derivations that agree today.
  ///
  /// Only `metadata` is named. The atServer merges it per key, so a sibling
  /// entry some later build added survives a write from this one — and the
  /// verb refuses `namespaces` and the approval state outright, so a key
  /// package amendment cannot widen the enrollment's own grant.
  Future<void> _publish(
      String enrolment, AtLookUp atLookUp, List<PackageKey> keys) async {
    final payload = KeyPackage.payloadFor(
      createdAt: DateTime.now().toUtc(),
      keys: keys,
    );
    await _enrollment.update(
        EnrollmentUpdateRequest(
          enrollmentId: enrolment,
          metadata: {
            // toJson, not the envelope: this is EnrollParams.metadata, which
            // is JSON-encoded onto the wire and read back as a Map by every
            // consumer.
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
      // Unreachable: AtClientPreference refuses a list naming an algorithm
      // this build cannot mint. Throwing rather than asserting, because the
      // two would have to have drifted apart for this to be reached.
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

  /// The keyfile's spelling of [alg] — what `keyPackageMaterials` reads back
  /// to recognise this as key-establishment material.
  final String materialAlgo;

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
