import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/secret_sharing/algo_ids.dart';

/// How far into the post-quantum rollout a client runs — every rollout axis set
/// as one value, applied at construction through `AtClientPreference.posture`.
///
/// A posture is a floor for what a client drives, never a downgrade of what an
/// atSign already holds.
class PqPosture {
  /// The algorithm the enrollment's APKAM **authentication** key is minted
  /// under, and the default for the `EnrollParams.signingAlgo` wire field.
  ///
  /// ⚠️ That wire name says "signing" and means authentication; a reader that
  /// finds it absent falls back to `rsa2048`.
  final SigningAlgoType authenticationKeyAlgorithm;

  /// Which algorithms the enrollment keeps an active **data signing** key for —
  /// the keys that sign what it attests to.
  ///
  /// ⚠️ Empty is not "unsigned": the enrollment signs with its APKAM
  /// authentication key, whose public half stays published as its signing key.
  final Set<SigningAlgoType> dataSigningKeyAlgorithms;

  /// Whether this client mints and publishes namespace encapsulation keys for
  /// the namespaces it uses, so that others can seal to them.
  final bool seedNamespaceKeys;

  /// The key-exchange mode an enrollment submission built under this posture
  /// uses. See `EnrollmentKeyExchangeMode` for what pq mode requires.
  final EnrollmentKeyExchangeMode keyExchangeMode;

  /// Whether the era `CryptoConfig` a client adopts writes post-quantum by
  /// default (`CryptoConfig.nskey`) or keeps writes legacy while reading
  /// everything (`CryptoConfig.readsNskeyWritesLegacy`).
  final bool writesPqByDefault;

  /// Whether this client configures the post-quantum crypto providers at all —
  /// and therefore whether it can **read** post-quantum-encrypted data.
  ///
  /// ⚠️ False switches off the whole post-quantum startup, so a record stamped
  /// with one of those provider ids throws `CryptoProviderNotRegistered`.
  final bool configuresPqProviders;

  /// Whether new data is refused rather than encrypted with the legacy
  /// provider.
  ///
  /// ⚠️ Settable only here: there is no per-preference override.
  final bool disallowLegacyEncryption;

  /// Whether onboarding an atSign mints the classical key material beside the
  /// post-quantum material.
  ///
  /// True in every named stage: when an atSign can stop holding legacy keys is
  /// an ecosystem-floor question no client-side stage can answer, so only a
  /// deployment that controls every client of its namespaces flips it.
  final bool mintLegacyMaterial;

  /// The key-establishment algorithms this client will seal to, strongest first
  /// — the **sender's** side of the choice.
  ///
  /// ⚠️ Narrowing it is choosing to refuse: a recipient advertising only a
  /// dropped algorithm is refused rather than downgraded.
  final List<String> sealsToKeyAlgorithms;

  /// The key-establishment algorithms this atSign **mints and advertises**, so
  /// that peers can seal to it — the receiver's side, where
  /// [sealsToKeyAlgorithms] is the sender's.
  ///
  /// Removing an entry retires that key rather than deleting it, so envelopes
  /// already sealed to it still open.
  final List<String> keyEstablishmentAlgorithms;

  /// A posture none of the named stages defines.
  ///
  /// Every axis is required: a defaulted one would hide the axes a caller never
  /// thought about among those it chose.
  factory PqPosture({
    required SigningAlgoType authenticationKeyAlgorithm,
    required Set<SigningAlgoType> dataSigningKeyAlgorithms,
    required bool seedNamespaceKeys,
    required EnrollmentKeyExchangeMode keyExchangeMode,
    required bool writesPqByDefault,
    required bool configuresPqProviders,
    required bool disallowLegacyEncryption,
    required bool mintLegacyMaterial,
    required List<String> sealsToKeyAlgorithms,
    required List<String> keyEstablishmentAlgorithms,
  }) {
    if (keyEstablishmentAlgorithms.isEmpty) {
      throw ArgumentError.value(
          keyEstablishmentAlgorithms,
          'keyEstablishmentAlgorithms',
          'an atSign that advertises no key-establishment key can receive '
              'nothing sealed to it. Name at least one algorithm');
    }
    if (disallowLegacyEncryption && !writesPqByDefault) {
      throw ArgumentError.value(
          disallowLegacyEncryption,
          'disallowLegacyEncryption',
          'a posture that refuses legacy writes while writing legacy by '
              'default refuses its own writes; set writesPqByDefault too');
    }
    if (writesPqByDefault && !configuresPqProviders) {
      throw ArgumentError.value(
          configuresPqProviders,
          'configuresPqProviders',
          'a posture that writes post-quantum data it cannot read seals '
              'records its own atSign cannot open; set configuresPqProviders too');
    }
    return PqPosture._(
      authenticationKeyAlgorithm: authenticationKeyAlgorithm,
      dataSigningKeyAlgorithms: dataSigningKeyAlgorithms,
      seedNamespaceKeys: seedNamespaceKeys,
      keyExchangeMode: keyExchangeMode,
      writesPqByDefault: writesPqByDefault,
      configuresPqProviders: configuresPqProviders,
      disallowLegacyEncryption: disallowLegacyEncryption,
      mintLegacyMaterial: mintLegacyMaterial,
      sealsToKeyAlgorithms: sealsToKeyAlgorithms,
      keyEstablishmentAlgorithms: keyEstablishmentAlgorithms,
    );
  }

  const PqPosture._({
    required this.authenticationKeyAlgorithm,
    required this.dataSigningKeyAlgorithms,
    required this.seedNamespaceKeys,
    required this.keyExchangeMode,
    required this.writesPqByDefault,
    required this.configuresPqProviders,
    required this.disallowLegacyEncryption,
    required this.mintLegacyMaterial,
    required this.sealsToKeyAlgorithms,
    required this.keyEstablishmentAlgorithms,
  });

  /// A client built before any of this: classical throughout, driving no
  /// upgrade, and unable to read post-quantum data at all.
  ///
  /// ⚠️ A record sealed to this atSign's namespace key is refused with
  /// `CryptoProviderNotRegistered`; an app that must read post-quantum data
  /// wants [pqReady].
  static const PqPosture legacy = PqPosture._(
    authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
    dataSigningKeyAlgorithms: {},
    seedNamespaceKeys: false,
    keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
    writesPqByDefault: false,
    configuresPqProviders: false,
    disallowLegacyEncryption: false,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: [SecretSharingAlgos.xWing],
  );

  /// **The credentials move and the data path does not**: the enrollment
  /// authenticates with ML-DSA-65, mints a fresh RSA-2048 *signing* key of its
  /// own, publishes a key package and seeds namespace keys, while still
  /// writing legacy data.
  ///
  /// It carries an atServer dependency [legacy] does not: ML-DSA PKAM.
  static const PqPosture pqReady = PqPosture._(
    authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
    dataSigningKeyAlgorithms: {SigningAlgoType.rsa2048},
    seedNamespaceKeys: true,
    keyExchangeMode: EnrollmentKeyExchangeMode.pq,
    writesPqByDefault: false,
    configuresPqProviders: true,
    disallowLegacyEncryption: false,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: [SecretSharingAlgos.xWing],
  );

  /// Post-quantum by default: against [pqReady] the data signing key becomes
  /// ML-DSA-65 and the post-quantum path becomes the default for encryption.
  ///
  /// ⚠️ Adoptable only by a deployment that controls every client of its
  /// namespaces and has seeded them — a destination with no published namespace
  /// key, and a write whose key carries no namespace, are both refused rather
  /// than written legacy.
  static const PqPosture pqActive = PqPosture._(
    authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
    dataSigningKeyAlgorithms: {SigningAlgoType.mldsa65},
    seedNamespaceKeys: true,
    keyExchangeMode: EnrollmentKeyExchangeMode.pq,
    writesPqByDefault: true,
    configuresPqProviders: true,
    disallowLegacyEncryption: true,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: [SecretSharingAlgos.xWing],
  );
}
