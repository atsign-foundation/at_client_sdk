import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/secret_sharing/algo_ids.dart';

/// How far into the post-quantum rollout a client runs — every rollout axis
/// set as one value.
///
/// A position, not a mechanism. Three constants name the stages the release
/// programme moves through — [legacy], [pqReady], [pqActive] — and a program
/// that needs a combination none of them expresses builds its own with the
/// unnamed constructor. Each axis still lives in its natural home and stays
/// independently settable on [AtClientPreference]; the posture is where a
/// stage's defaults are stated once, so an app can run tomorrow's stage today,
/// or a test drive the whole rollout, without hunting down the knobs one by
/// one.
///
/// **A posture is a floor, never a downgrade.** Key material wins for
/// authenticating and reading: [legacy] means "do not drive an upgrade", not
/// "return to legacy", so a client built against an older at_client cannot
/// un-retrofit an atSign that has already moved. Verification and decryption
/// are maximal under every posture and are not settable here at all, which is
/// what makes reads universal by construction rather than by agreement.
///
/// The axes:
///
/// - **Which key authenticates a connection** — [authenticationKeyAlgorithm],
///   the algorithm a retrofit mints the enrollment's APKAM key under. Only the
///   atServer verifies this key, and it is the operator's own infrastructure.
/// - **Which keys sign what the enrollment attests to** —
///   [dataSigningKeyAlgorithms]. Empty means the enrollment holds no signing
///   key of its own and its authentication key signs, which is what every
///   released build does. Every *peer* verifies these, and the fleet is not
///   the operator's to upgrade — which is the whole reason the two are
///   separate axes rather than one stage name.
/// - **Whether namespace keys are seeded** — [seedNamespaceKeys], minting and
///   publishing the encapsulation keys other atSigns seal to.
/// - **How an enrollment's `apkamSymmetricKey` travels** — [keyExchangeMode].
/// - **What encrypts new data** — [writesPqByDefault] selects the era
///   `CryptoConfig` a client adopts at construction: the nskey provider set
///   with writes still legacy, or with post-quantum writes the default. An
///   explicit [AtClientPreference.crypto] always wins.
/// - **Whether legacy writes are refused** — [disallowLegacyEncryption].
/// - **Whether onboarding mints legacy material** — [mintLegacyMaterial].
/// - **Which key-establishment algorithms this client will seal to** —
///   [sealsToKeyAlgorithms].
///
/// Two rows of the rollout table are deliberately **not** fields here. A key
/// package published for secret sharing is a consequence of [keyExchangeMode]
/// being [EnrollmentKeyExchangeMode.pq] — pq mode is submitted with its two
/// companions built alongside — rather than a decision of its own. And
/// [mintLegacyMaterial] and [keyExchangeMode] are both at_auth values that
/// at_client only *carries*: at_client submits no app enrollment, so they take
/// effect when the app builds its `AtEnrollmentRequest` from the posture.
///
/// The posture is **applied at construction**: it rides
/// [AtClientPreference.posture] into the client, and the construction-time
/// axes cannot move for a live client.
class PqPosture {
  /// The algorithm the enrollment's APKAM **authentication** key is minted
  /// under — the default for `selfRetrofit`'s `signingAlgo` parameter and,
  /// through it, for the `EnrollParams.signingAlgo` wire field.
  ///
  /// ⚠️ **Both of those names say "signing" and both mean *authentication*.**
  /// The wire field has named the APKAM key's algorithm since before an
  /// enrollment had signing keys of its own, and renaming it is a multi-repo
  /// seam against a released atServer where a stale reader seeing an absent
  /// field falls back to `rsa2048` — a silent wrong-algorithm PKAM. The name
  /// stays out there; nothing on this side repeats the mistake.
  final SigningAlgoType authenticationKeyAlgorithm;

  /// Which algorithms the enrollment keeps an active **data signing** key for
  /// — the keys that sign what it attests to.
  ///
  /// **Empty is not "unsigned".** An enrollment with no signing key of its own
  /// signs with its APKAM authentication key, whose public half is published as
  /// its signing key and stays published, because that is what verifies every
  /// envelope signed before the two jobs were separated.
  ///
  /// ⚠️ **What is minted at creation is always `rsa2048`, whatever this set
  /// holds.** The `_apsk` advertisement has to stay the bare public-key string
  /// an un-upgraded peer can parse, and only a single active `rsa2048` entry
  /// spells that way; a posture wanting ML-DSA reaches it by *retiring* the RSA
  /// key afterwards, not by skipping it. A retired key stays advertised, which
  /// is what keeps everything it signed verifiable.
  final Set<SigningAlgoType> dataSigningKeyAlgorithms;

  /// Whether this client mints and publishes namespace encapsulation keys for
  /// the namespaces it uses, so that others can seal to them.
  ///
  /// Seeding is a rollout action, not a crypto-path one, and it comes a stage
  /// *before* post-quantum writes on purpose: clients mint and publish while
  /// still writing legacy, so that by the time post-quantum writes switch on
  /// the keys are already everywhere. Gating it on the PQ path being active
  /// would seed nothing until the moment seeding stopped being useful.
  final bool seedNamespaceKeys;

  /// The key-exchange mode an enrollment submission built under this posture
  /// uses. See `EnrollmentKeyExchangeMode` for what pq mode requires.
  final EnrollmentKeyExchangeMode keyExchangeMode;

  /// Whether the era `CryptoConfig` a client adopts writes post-quantum by
  /// default (`CryptoConfig.nskey`) or keeps writes legacy while reading
  /// everything (`CryptoConfig.readsNskeyWritesLegacy`).
  final bool writesPqByDefault;

  /// Whether new data is refused rather than encrypted with the legacy
  /// provider.
  ///
  /// ⚠️ **Settable only here.** Unlike the algorithm lists, this one has no
  /// per-preference override: a safety flag whose escape hatch defeats its
  /// purpose is not the same kind of thing as deployment policy. An app that
  /// wants it on ahead of the release schedule adopts [pqActive], or builds a
  /// posture that says so.
  final bool disallowLegacyEncryption;

  /// Whether onboarding an atSign mints the classical key material beside the
  /// post-quantum material.
  ///
  /// True in all three released stages: the ecosystem floor decides when an
  /// atSign can stop holding legacy keys, and no client-side stage can know
  /// that. It is an axis so that the stop-release, and a deployment that
  /// controls every client of its namespaces, can flip it deliberately.
  final bool mintLegacyMaterial;

  /// The key-establishment algorithms this client will seal to, strongest
  /// first — the **sender's** side of the choice.
  ///
  /// Ordering, and only incidentally restriction. A sender picks the first of
  /// these that the recipient advertises, so the order is a preference over
  /// what a recipient offers rather than a judgement that one is stronger:
  /// the two are chosen for different reasons, and which an atSign *publishes*
  /// is its own configuration, not this.
  ///
  /// ⚠️ **Narrowing it is choosing to refuse.** The default is everything this
  /// build can seal under, so nobody is refused by accident; drop an entry and
  /// a recipient advertising only that algorithm has no construction in common
  /// with this client, and the write is refused rather than downgraded. That
  /// is the point for a deployment under a FIPS-only rule, and it is a real
  /// cost — the two atSigns then cannot exchange data at all. Which is why the
  /// default never imposes it.
  ///
  /// Identical in all three released stages, deliberately: which KEM is
  /// acceptable is a **deployment** decision, not a rollout position, so the
  /// stages have nothing to say about it. It is an axis so a deployment can
  /// state it in the same place as everything else it states.
  final List<String> sealsToKeyAlgorithms;

  /// The key-establishment algorithms this atSign **mints and advertises**, so
  /// that peers can seal to it — the receiver's side, where
  /// [sealsToKeyAlgorithms] is the sender's.
  ///
  /// **One entry is the ordinary state and the default.** Unlike the sender's
  /// list, where every omission refuses somebody, an entry here costs a
  /// keypair minted, filed and advertised for the life of the enrollment — and
  /// buys nothing on its own, because a sender needs only one construction in
  /// common. Advertising both KEMs is what a **migration** looks like, not
  /// what a healthy deployment looks like.
  ///
  /// So a second entry means: offer both while peers catch up, then drop the
  /// first. An enrollment holds at most one active key per algorithm — the
  /// keyfile's own assurance rule — so the list is exactly the set of active
  /// keys the enrollment's package advertises. Removing an entry **retires**
  /// that key rather than deleting it: envelopes already sealed to it still
  /// open, and senders stop addressing it.
  ///
  /// Identical in all three released stages, for the same reason
  /// [sealsToKeyAlgorithms] is: which KEM an atSign publishes is a
  /// **deployment** decision rather than a rollout position. It is an axis so
  /// that a deployment states it where it states everything else.
  final List<String> keyEstablishmentAlgorithms;

  /// A posture no released stage defines.
  ///
  /// Every axis is required: a defaulted one would hide the axes a caller
  /// never thought about among those it chose, which is exactly what the three
  /// constants are for.
  factory PqPosture({
    required SigningAlgoType authenticationKeyAlgorithm,
    required Set<SigningAlgoType> dataSigningKeyAlgorithms,
    required bool seedNamespaceKeys,
    required EnrollmentKeyExchangeMode keyExchangeMode,
    required bool writesPqByDefault,
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
    return PqPosture._(
      authenticationKeyAlgorithm: authenticationKeyAlgorithm,
      dataSigningKeyAlgorithms: dataSigningKeyAlgorithms,
      seedNamespaceKeys: seedNamespaceKeys,
      keyExchangeMode: keyExchangeMode,
      writesPqByDefault: writesPqByDefault,
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
    required this.disallowLegacyEncryption,
    required this.mintLegacyMaterial,
    required this.sealsToKeyAlgorithms,
    required this.keyEstablishmentAlgorithms,
  });

  /// The default: classical throughout, and driving no upgrade.
  ///
  /// Reads are fully post-quantum-capable — they are under every posture — but
  /// nothing this client writes, enrolls or retrofits outruns what the rest of
  /// the fleet can read. The enrollment holds no signing key of its own, its
  /// APKAM authentication key signs, and `_apsk` advertises that key as the
  /// bare public key string everything deployed can parse.
  static const PqPosture legacy = PqPosture._(
    authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
    dataSigningKeyAlgorithms: {},
    seedNamespaceKeys: false,
    keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
    writesPqByDefault: false,
    disallowLegacyEncryption: false,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: [SecretSharingAlgos.xWing],
  );

  /// **The credentials move and the data path does not.**
  ///
  /// The enrollment authenticates with ML-DSA-65, mints a fresh RSA-2048
  /// *signing* key of its own, publishes a key package, seeds namespace keys —
  /// and goes on writing legacy data. The two keys have different audiences,
  /// and that is the whole reason this stage exists: an APKAM public key sits
  /// on the enrollment record where anyone can harvest it, so an adversary who
  /// breaks RSA later can forge authentication for any enrollment that never
  /// moved, while what peers verify is not asked to move at all.
  ///
  /// The advertisement stays the bare string — one active `rsa2048` entry — so
  /// an un-upgraded peer cannot tell this sender from a [legacy] one. What it
  /// does carry is an atServer dependency [legacy] does not: ML-DSA PKAM.
  static const PqPosture pqReady = PqPosture._(
    authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
    dataSigningKeyAlgorithms: {SigningAlgoType.rsa2048},
    seedNamespaceKeys: true,
    keyExchangeMode: EnrollmentKeyExchangeMode.pq,
    writesPqByDefault: false,
    disallowLegacyEncryption: false,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: [SecretSharingAlgos.xWing],
  );

  /// Post-quantum by default: the split is complete and the data path has
  /// moved with it.
  ///
  /// Exactly two things change against [pqReady] — the data signing key becomes
  /// ML-DSA-65, and the post-quantum path becomes the default for encryption.
  /// The RSA-2048 signing key [pqReady] used stays advertised as `retired`, so
  /// everything **that key** signed still verifies.
  ///
  /// RSA is deliberately not beside ML-DSA in [dataSigningKeyAlgorithms]. A
  /// verifier takes the strongest algorithm the envelope and the signer's
  /// advertisement have in common, so a second, weaker signature is only ever
  /// the one that is passed over: it would cost a key, an advertisement entry
  /// and a signature per envelope to be ignored.
  ///
  /// **This is a later stage than the default, adoptable early only with eyes
  /// open.** It exists so the whole rollout is drivable from one codebase — the
  /// acceptance suite runs it, and a deployment that controls every client of
  /// its namespaces can run it once those namespaces are seeded. Two
  /// consequences to accept:
  ///
  /// - a destination with no published namespace key is **refused**, never
  ///   written legacy;
  /// - a write whose key carries **no namespace** is refused, because no
  ///   post-quantum scheme serves one: the nskey data path is
  ///   `(owner, namespace)`-scoped throughout, so every provider declines such
  ///   a key and the only fallback is legacy. An app hits this if it hands the
  ///   SDK a key with neither its own namespace nor one on the preference.
  ///
  /// The readers for everything this posture emits — the nskey records among
  /// them — ship in the **same release line as the posture itself**, so its
  /// peers must be on at least that release, not merely "any 3.x".
  static const PqPosture pqActive = PqPosture._(
    authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
    dataSigningKeyAlgorithms: {SigningAlgoType.mldsa65},
    seedNamespaceKeys: true,
    keyExchangeMode: EnrollmentKeyExchangeMode.pq,
    writesPqByDefault: true,
    disallowLegacyEncryption: true,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
    keyEstablishmentAlgorithms: [SecretSharingAlgos.xWing],
  );
}
