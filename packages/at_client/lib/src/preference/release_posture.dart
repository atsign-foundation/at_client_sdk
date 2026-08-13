import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;

/// The post-quantum rollout's five flags, set as a group.
///
/// From the rollout's point of view, at_client 4.0 is the *same code* as
/// final 3.x with different flag defaults (`docs/projects/pq/decisions.md`
/// 56.4): every stage of the migration ships in 3.x behind a flag, and the
/// major version is a pure default flip. Each flag lives in its natural home
/// and is independently settable; this type is the convenience that names a
/// release's defaults as one value, so an app can run tomorrow's posture
/// today — or a test can drive the whole rollout — without hunting down five
/// knobs:
///
/// - **What encrypts new data** — [writesPqByDefault] selects the era
///   `CryptoConfig` a client adopts at construction: the nskey provider set
///   with writes still legacy (3.x), or with post-quantum writes the default
///   (4.0). An explicit [AtClientPreference.crypto] always wins.
/// - **Whether legacy writes are refused** —
///   [AtClientPreference.disallowLegacyEncryption]. An explicit constructor
///   argument wins.
/// - **How an enrollment's `apkamSymmetricKey` travels** — [keyExchangeMode].
///   Enrollment submission goes through `package:at_auth`, which cannot see a
///   preference, so this value is applied by whoever builds the
///   `AtEnrollmentRequest` — and pq mode needs its two companions built
///   alongside (`enrollmentKeyPackageBuilder`, the symmetric-key resolver),
///   exactly as the request's own documentation describes.
/// - **What a self-retrofit mints** — [retrofitSigningAlgo], the default for
///   `selfRetrofit`'s `signingAlgo` parameter. An explicit argument wins.
/// - **Which signing keys an enrollment holds** —
///   [inUseSigningAlgorithms], the default for
///   [AtClientPreference.inUseSigningAlgorithms]. An explicit constructor
///   argument wins.
///
/// The posture is **applied at construction**: it rides
/// [AtClientPreference.posture] into the client, and the construction-time
/// flags cannot move for a live client. The per-operation flags
/// ([keyExchangeMode], [retrofitSigningAlgo]) are only *defaults* — every
/// call site still takes the per-call value first.
///
/// There are exactly two postures and no general constructor, deliberately: a
/// posture means "the defaults of a release", and an app that wants a mixture
/// sets the individual flag it cares about beside the posture rather than
/// minting a hybrid posture no release ever shipped.
class ReleasePosture {
  /// Whether the era `CryptoConfig` a client adopts writes post-quantum by
  /// default (`CryptoConfig.nskey`) or keeps writes legacy while reading
  /// everything (`CryptoConfig.readsNskeyWritesLegacy`).
  final bool writesPqByDefault;

  /// The default for [AtClientPreference.disallowLegacyEncryption].
  final bool disallowLegacyEncryption;

  /// The key-exchange mode an enrollment submission built under this posture
  /// uses. See `EnrollmentKeyExchangeMode` for what pq mode requires.
  final EnrollmentKeyExchangeMode keyExchangeMode;

  /// The signing algorithm `selfRetrofit` mints when the caller names none.
  final SigningAlgoType retrofitSigningAlgo;

  /// The signing algorithms an enrollment keeps an active signing key for
  /// under this posture. See [AtClientPreference.inUseSigningAlgorithms] for
  /// what naming one means and what an empty set leaves in place.
  final Set<SigningAlgoType> inUseSigningAlgorithms;

  /// The 3.x defaults — the migration under way.
  ///
  /// Reads are fully post-quantum-capable; writes, enrollments and retrofits
  /// stay classical, so nothing this client produces outruns what the rest of
  /// the fleet can read. The envelope is not an axis here — there is one
  /// shape, emitted under every posture.
  ///
  /// [inUseSigningAlgorithms] is empty for the same reason. An enrollment that
  /// holds a signing key of its own holds *two* keys — that one and the APKAM
  /// authentication key, which stays published for as long as the envelopes it
  /// signed must verify — and two keys cannot be advertised as the bare public
  /// key string that everything deployed can read.
  const ReleasePosture.migration()
      : writesPqByDefault = false,
        disallowLegacyEncryption = false,
        keyExchangeMode = EnrollmentKeyExchangeMode.legacy,
        retrofitSigningAlgo = SigningAlgoType.rsa2048,
        inUseSigningAlgorithms = const {};

  /// The 4.0 defaults — post-quantum by default.
  ///
  /// New data is written under the nskey data path, legacy writes are
  /// refused, and a retrofit mints ML-DSA. [keyExchangeMode] becomes pq, which — unlike the others — this
  /// posture cannot apply on its own: at_client submits no app enrollment,
  /// so that value takes effect when the app builds its request from it
  /// (`AtEnrollmentRequest.pq`).
  ///
  /// **This is tomorrow's posture, adoptable today only with eyes open.** It
  /// exists so the whole rollout is drivable from one codebase — the
  /// acceptance suite runs it, and a deployment that controls every client
  /// of its namespaces can run it once those namespaces are seeded. Two
  /// consequences to accept before adopting it early:
  ///
  /// - a destination with no published namespace key is **refused**, never
  ///   written legacy — and seeding is a separate, deliberate knob
  ///   ([AtClientPreference.seedNamespaceKeys]), not something this posture
  ///   turns on;
  /// - the SDK's own namespace-less internal writes (the sync and
  ///   notification watermarks among them) are refused under this posture
  ///   today: no post-quantum scheme serves a key with no namespace, and
  ///   the 4.0 release owes a decision on those writes before this posture
  ///   can become the default (the R-2 project in `docs/projects/pq/`).
  ///
  /// The readers for everything this posture emits — the nskey records among
  /// them — ship in the **same release line as the posture itself**, so its
  /// peers must be on at least that release, not merely "any 3.x".
  ///
  /// [inUseSigningAlgorithms] is ML-DSA alone, and RSA is deliberately not
  /// beside it. A verifier takes the strongest algorithm the envelope and the
  /// signer's advertisement have in common, so a second, weaker signature is
  /// only ever the one that is passed over: it would cost a key, an
  /// advertisement entry and a signature per envelope to be ignored. What
  /// keeps older envelopes verifiable is not a weaker key in this set, it is
  /// the APKAM authentication key staying published after it stops signing.
  const ReleasePosture.postQuantum()
      : writesPqByDefault = true,
        disallowLegacyEncryption = true,
        keyExchangeMode = EnrollmentKeyExchangeMode.pq,
        retrofitSigningAlgo = SigningAlgoType.mldsa65,
        inUseSigningAlgorithms = const {SigningAlgoType.mldsa65};
}
