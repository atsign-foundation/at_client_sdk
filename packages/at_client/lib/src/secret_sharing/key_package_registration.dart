import 'dart:convert' show base64Decode, base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart' show AtKemAlgorithm;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_client/src/secret_sharing/enrollment_directory.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:meta/meta.dart' show experimental, protected;

/// One of this APKAM keypair's enc keypairs, as it is persisted.
///
/// [encSeed] is the base64 of the KEM's secret **seed**; the public key and the
/// decapsulation key both re-derive from it deterministically. The seed rather
/// than the secret key, because the two are only the same thing for X-Wing.
/// ML-KEM's secret key is an expanded decapsulation key that no seeded call
/// reproduces, so a keyfile holding one could never recover the public half —
/// see `AtKemAlgorithm.keyPairFromSeed`.
///
/// [keyAlgo] says which KEM the seed belongs to, and it must be stored
/// alongside it: 32 bytes and 64 bytes are both valid seeds for *some* backend,
/// so the bytes alone do not identify one, and expanding a seed under the wrong
/// KEM yields a key whose kpid nobody is writing to.
///
/// [status] is what makes holding more than one useful. A retired key is not
/// advertised for new traffic and nothing is sealed to it from now on, but it
/// is still expanded and still opens envelopes already addressed to it — which
/// is the whole reason it is kept.
@experimental
class PersistedEncKey {
  final String encSeed;

  /// An id from [SecretSharingAlgos.keyAlgos]. Defaults to the hybrid, which
  /// is what every seed written before this field existed was.
  final String keyAlgo;

  /// Defaults to [KeyEntryStatus.active], which is what every seed written
  /// before this field existed was — there was only ever one. An open token:
  /// ask [offeredForNewOperations] rather than comparing it.
  final KeyEntryStatus status;

  /// Whether this is the key the enrollment advertises and is addressed at —
  /// see [KeyEntryStatus.offersNewOperations]. A key that is not still opens
  /// what is already in flight to it.
  bool get offeredForNewOperations =>
      KeyEntryStatus.offersNewOperations(status);

  PersistedEncKey({
    required this.encSeed,
    this.keyAlgo = SecretSharingAlgos.xWing,
    this.status = KeyEntryStatus.active,
  });
}

/// This APKAM keypair's enc keypairs, persisted (by an app callback) across
/// restarts.
///
/// These are the per-APKAM recipient keypairs: they belong to the APKAM keypair
/// (one set per keyfile), so a copied keyfile shares them — a copy is the same
/// recipient identity, which is the intended per-APKAM granularity.
///
/// A **list**, because rotating an enc key has to be non-lossy. `envelopeTtl`
/// is seven days, so at the moment a client starts advertising a new key there
/// is up to a week of traffic still addressed to the old one; a client that
/// held only the new key could not open any of it. The superseded key is
/// therefore retained as [KeyEntryStatus.retired] and expanded alongside the
/// active one.
@experimental
class PersistedApkamKeys {
  /// Exactly one entry should be [KeyEntryStatus.active] per algorithm — that
  /// is the key this APKAM keypair advertises and is addressed at. The rest are
  /// retained for opening what is still in flight to them.
  final List<PersistedEncKey> encKeys;

  PersistedApkamKeys({required this.encKeys});

  /// The one-key holding, which is what a client that has never rotated has.
  PersistedApkamKeys.single({
    required String encSeed,
    String keyAlgo = SecretSharingAlgos.xWing,
  }) : encKeys = [PersistedEncKey(encSeed: encSeed, keyAlgo: keyAlgo)];
}

/// One enc keypair this client holds, expanded from its persisted seed.
///
/// Private because it carries the decapsulation key: the mixin hands out the
/// public half freely and the secret half only through [
/// KeyPackageRegistration.encKeyFor], which answers for a specific kid.
class _HeldEncKey {
  final Uint8List seed;
  final Uint8List publicKey;

  /// What `pqOpen` takes — not the seed, which for ML-KEM is a different thing.
  final Uint8List secretKey;

  final String keyAlgo;
  final KeyEntryStatus status;

  bool get offeredForNewOperations =>
      KeyEntryStatus.offersNewOperations(status);

  _HeldEncKey({
    required this.seed,
    required this.publicKey,
    required this.secretKey,
    required this.keyAlgo,
    required this.status,
  });

  /// This key's addressing token — the SHA-256 prefix of its public half.
  late final String kid = PackageKey.computeKid(base64Encode(publicKey));

  PackageKey get advertised => PackageKey.fromBytes(
      use: SecretSharingAlgos.useEnc,
      alg: keyAlgo,
      pub: publicKey,
      status: status);
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

  final List<_HeldEncKey> _encKeys = [];
  bool _registered = false;
  EnrollmentDirectory? _directory;

  /// The atServer-backed key-package directory. Defaults to a verb-backed
  /// implementation; tests assign a fake.
  EnrollmentDirectory get directory =>
      _directory ??= VerbEnrollmentDirectory(atClient);

  set directory(EnrollmentDirectory value) => _directory = value;

  bool get isRegistered => _registered;

  /// The key this client currently advertises and is addressed at: the
  /// strongest active one in [SecretSharingAlgos.keyAlgos] order.
  ///
  /// The same rule [KeyPackage.bestKeyFor] applies to the advertised package,
  /// and it has to stay the same rule. If this side and the package disagreed
  /// the client would listen at one address while telling peers to write to
  /// another, and nothing would ever arrive — the drift
  /// [PairwiseSecretSharing] warns about, from the holder's side.
  _HeldEncKey get _activeEncKey {
    if (_encKeys.isEmpty) {
      throw StateError('register() has not been called');
    }
    for (final alg in SecretSharingAlgos.keyAlgos) {
      for (final held in _encKeys) {
        if (held.keyAlgo == alg && held.offeredForNewOperations) {
          return held;
        }
      }
    }
    throw StateError(
        'this client holds ${_encKeys.length} enc key(s) and not one of them '
        'is active, so it advertises no address for new traffic. Their '
        'statuses are ${_encKeys.map((k) => '"${k.status}"').join(', ')}. '
        'A key that is not active is retained to open what is already in '
        'flight to it; it is not something to be reached at.');
  }

  /// This APKAM keypair's encapsulation public key (raw bytes) — the active
  /// one. Throws [StateError] until [register] has completed.
  Uint8List get encPublicKey => _activeEncKey.publicKey;

  /// The **decapsulation key** for the key [kid] names, and which KEM it
  /// belongs to — for opening by composing mixins, not for application use.
  /// Null if this client holds no such key.
  ///
  /// By kid rather than "the current one", because a retired key still opens
  /// what was sealed to it before it was retired, and that is the only reason
  /// it is still held. The envelope names the key it was sealed to; this
  /// answers whether that is a key this client has.
  ///
  /// Not the seed: this is what `pqOpen` takes, and for ML-KEM the two differ.
  /// It is derived from the persisted seed at [register] time so a caller never
  /// has to know which.
  @protected
  ({Uint8List secretKey, String keyAlgo})? encKeyFor(String kid) {
    for (final held in _encKeys) {
      if (held.kid == kid) {
        return (secretKey: held.secretKey, keyAlgo: held.keyAlgo);
      }
    }
    return null;
  }

  /// Every address this client can be reached at — the active key's and every
  /// retired key's.
  ///
  /// A sweep filters on these rather than on [kpid] alone. A sender that read
  /// the package before a rotation addresses the superseded key, and an
  /// envelope this client never scans for is one it never opens however
  /// willing [encKeyFor] is to open it.
  Set<String> get heldKpids => {for (final held in _encKeys) held.kid};

  /// Which KEM [encPublicKey] belongs to — an id from
  /// [SecretSharingAlgos.keyAlgos]. Throws [StateError] until [register]
  /// completes.
  String get encKeyAlgo => _activeEncKey.keyAlgo;

  /// The KEM this client would mint a *fresh* key under — the **primary**,
  /// first of [AtClientPreference.keyEstablishmentAlgorithms].
  ///
  /// Not necessarily [encKeyAlgo]: a client that loaded an existing key keeps
  /// that key's algorithm, because its kpid is the address its enrollment
  /// already advertised.
  ///
  /// Singular where the preference is now a list, because this answers "what
  /// would this client mint if it held nothing" — one key. Reconciling the
  /// enrollment's package against the whole list is `KeyPackageMinting`'s job,
  /// which runs at startup once a client exists.
  String get configuredKeyAlgo =>
      atClient.getPreferences()?.keyEstablishmentAlgorithms.first ??
      SecretSharingAlgos.xWing;

  /// This key package's addressing id ([KeyPackage.kpid]) — the SHA-256 prefix
  /// of the **active** encapsulation public key. Throws [StateError] until
  /// [register] completes.
  String get kpid => _activeEncKey.kid;

  /// This APKAM keypair's key package (the one registered for discovery).
  /// Throws [StateError] until [register] has generated the enc keypair.
  ///
  /// Every key this client holds is advertised, each carrying its own status: a
  /// retired one is listed so that a peer holding an envelope still in flight
  /// can see whose key it was, and skipped by [KeyPackage.bestKeyFor] so that
  /// nothing new is sealed to it.
  ///
  /// `suites` is derived from the advertised keys rather than stated, so it can
  /// never claim a construction this holder's own keys cannot decapsulate.
  KeyPackage get myKeyPackage {
    // Reading the active key first so that a client holding nothing usable
    // throws here rather than advertising a package with no address in it.
    _activeEncKey;
    return KeyPackage(
      enrollmentId: enrollmentId,
      createdAt: DateTime.now().toUtc(),
      keys: [for (final held in _encKeys) held.advertised],
    );
  }

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
  Future<SignedEnvelope> signedKeyPackagePayload() async =>
      await wrapAndSign(myKeyPackage.toJson(), type: EnvelopeType.keyPackage);

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
    if (_encKeys.isEmpty) {
      final loaded = await loadApkamKeys?.call();
      if (loaded == null) {
        _encKeys.add(await _mintEncKey(configuredKeyAlgo));
        await saveApkamKeys?.call(PersistedApkamKeys(encKeys: [
          for (final held in _encKeys)
            PersistedEncKey(
                encSeed: base64Encode(held.seed),
                keyAlgo: held.keyAlgo,
                status: held.status),
        ]));
      } else {
        if (loaded.encKeys.isEmpty) {
          throw StateError(
              'loadApkamKeys returned a holding with no keys in it. An app '
              'with nothing to restore returns null, which mints a fresh key; '
              'an empty list says "these are the keys" and names none, and '
              'minting one anyway would answer at an address this enrollment '
              'never advertised.');
        }
        for (final entry in loaded.encKeys) {
          _encKeys.add(await _expandEncKey(entry));
        }
      }
    }
    await publishPublicSigningKey();
    _registered = true;
    logger.info('Prepared $encKeyAlgo key package for enrollment '
        '$enrollmentId (kpid $kpid, ${_encKeys.length} key(s) held)');
    return myKeyPackage;
  }

  /// A fresh active enc keypair under [algo].
  Future<_HeldEncKey> _mintEncKey(String algo) async {
    final seed = _kemFor(algo).newSeed();
    return _heldFrom(seed, algo, KeyEntryStatus.active);
  }

  /// One persisted entry, expanded back into the keypair it names.
  ///
  /// A loaded key keeps its OWN algorithm, whatever the preference now says.
  /// Its kpid is the address this enrollment already advertised, and re-minting
  /// under a different KEM would move that address to one nobody is writing to
  /// — the client would scan for envelopes that are being sent somewhere else.
  /// Changing the preference therefore takes effect on the next enrollment, not
  /// on this one.
  Future<_HeldEncKey> _expandEncKey(PersistedEncKey entry) async {
    if (entry.offeredForNewOperations && entry.keyAlgo != configuredKeyAlgo) {
      logger.info(
          'This enrollment holds a ${entry.keyAlgo} key package and the '
          'preference asks for $configuredKeyAlgo. Keeping the '
          '${entry.keyAlgo} one: the kpid is the address peers already seal '
          'to. A new enrollment will mint $configuredKeyAlgo.');
    }
    return _heldFrom(base64Decode(entry.encSeed), entry.keyAlgo, entry.status);
  }

  /// The SEED is what is persisted and what everything re-derives from. Storing
  /// the secret key instead is correct only for X-Wing, whose secret key IS its
  /// seed; ML-KEM's is an expanded decapsulation key that nothing turns back
  /// into a public half.
  Future<_HeldEncKey> _heldFrom(
      Uint8List seed, String algo, KeyEntryStatus status) async {
    final kp = await _kemFor(algo).keyPairFromSeed(seed);
    return _HeldEncKey(
      seed: seed,
      publicKey: kp.publicKey,
      secretKey: kp.secretKey,
      keyAlgo: algo,
      status: status,
    );
  }

  AtKemAlgorithm _kemFor(String algo) {
    final AtKemAlgorithm? kem = SecretSharingAlgos.kemFor(algo);
    if (kem == null) {
      throw StateError(
          'No key-establishment implementation for "$algo" — this client '
          'cannot mint or recover a key package. Supported: '
          '${SecretSharingAlgos.keyAlgos}');
    }
    return kem;
  }
}
