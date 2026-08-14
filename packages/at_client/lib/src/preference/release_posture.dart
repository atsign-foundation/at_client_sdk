import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;

/// Where a build stands in the rollout that separates an enrollment's
/// **signing** keys from the APKAM key that **authenticates** its connections.
///
/// A position, not a mechanism. Three writer behaviours move together — mint
/// signing keys of one's own, publish `_apsk` as an array, emit an envelope
/// with one signature per key — and a build doing any one without the others
/// emits something the rest of the fleet cannot handle. They are inseparable
/// by construction rather than by agreement: the array form and the second
/// signature are both *consequences* of the enrollment holding a second key,
/// so naming the stage names all three.
enum SigningRollout {
  /// One key does both jobs, as every released build does. The APKAM
  /// authentication key signs, and `_apsk` advertises it — as the bare public
  /// key string where that key is RSA, which is the form every deployed reader
  /// parses.
  now,

  /// **The quantum-forgeable credential moves, and the one the fleet verifies
  /// does not.** The enrollment authenticates with ML-DSA-65 and mints a fresh
  /// RSA-2048 *signing* key, which is what `_apsk` advertises — as the bare
  /// string every deployed reader parses, because it is a single active
  /// `rsa2048` entry.
  ///
  /// The two keys have different audiences, and that is the whole reason this
  /// stage exists. Only the **atServer** verifies the authentication key, and
  /// it is the operator's own infrastructure; **every peer** verifies the
  /// signing key, and the fleet is not the operator's to upgrade. An APKAM
  /// public key sits on the enrollment record where anyone can harvest it, so
  /// an adversary who breaks RSA later can forge authentication for any
  /// enrollment that never moved.
  ///
  /// Entered only by a **new** enrollment: an existing [now] enrollment stays
  /// where it is until it retrofits, and the retrofit mints a new enrollment
  /// id with both keys. That is what keeps this stage free of an APKAM
  /// rotation.
  rollout1,

  /// The split is complete: this enrollment signs with ML-DSA-65, and the
  /// RSA-2048 signing key it used to sign with is retained in `_apsk` as
  /// `retired` so that everything **that key** signed still verifies.
  rollout2;

  /// What [AtClientPreference.inUseSigningAlgorithms] defaults to at this
  /// stage. The set is the thing a client obeys; this is where its default
  /// comes from, so a stage and a behaviour cannot drift apart.
  Set<SigningAlgoType> get defaultInUseSigningAlgorithms => switch (this) {
        // No signing key of its own: the authentication key signs, and `_apsk`
        // advertises that key — which is what every released build does.
        SigningRollout.now => const {},
        // One rsa2048 signing key, which is exactly what the bare `_apsk`
        // string can express. A second algorithm here would force the array.
        SigningRollout.rollout1 => const {SigningAlgoType.rsa2048},
        SigningRollout.rollout2 => const {SigningAlgoType.mldsa65},
      };

  /// The algorithm of the **authentication** key a retrofit mints at this
  /// stage — the default for `selfRetrofit`'s `signingAlgo` parameter and,
  /// through it, for the `EnrollParams.signingAlgo` wire field.
  ///
  /// ⚠️ **Both of those names say "signing" and both mean *authentication*.**
  /// The wire field has named the APKAM key's algorithm since before an
  /// enrollment had signing keys of its own, and renaming it is a multi-repo
  /// seam against a released atServer where a stale reader seeing an absent
  /// field falls back to `rsa2048` — a silent wrong-algorithm PKAM. The name
  /// stays; this one does not repeat the mistake.
  ///
  /// Derived here beside [defaultInUseSigningAlgorithms] rather than stored
  /// on [ReleasePosture]: two stored fields would be two controls over one
  /// position, and an operator who set the stage but forgot the algorithm
  /// would land in a state no release defines with nothing to tell them.
  SigningAlgoType get defaultRetrofitAuthenticationAlgo => switch (this) {
        SigningRollout.now => SigningAlgoType.rsa2048,
        SigningRollout.rollout1 ||
        SigningRollout.rollout2 =>
          SigningAlgoType.mldsa65,
      };
}

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
/// - **Where the auth/signing split stands** — [signingRollout], the one
///   value both remaining defaults derive from:
///   [SigningRollout.defaultInUseSigningAlgorithms] for
///   [AtClientPreference.inUseSigningAlgorithms], and
///   [SigningRollout.defaultRetrofitAuthenticationAlgo] for what a
///   self-retrofit's **authentication** key is minted as. An explicit
///   constructor argument, or an explicit `signingAlgo` at the retrofit call,
///   wins over either.
///
/// The posture is **applied at construction**: it rides
/// [AtClientPreference.posture] into the client, and the construction-time
/// flags cannot move for a live client. The per-operation flags
/// ([keyExchangeMode], [retrofitAuthenticationAlgo]) are only *defaults* —
/// every call site still takes the per-call value first.
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

  /// Where this posture stands in the auth/signing split.
  final SigningRollout signingRollout;

  /// The **authentication** key's algorithm a retrofit mints under this
  /// posture when the caller names none — **derived** from [signingRollout],
  /// never stored beside it, for the same reason
  /// [inUseSigningAlgorithms] is.
  ///
  /// ⚠️ **A posture is not always the effective stage.** An app may set
  /// [AtClientPreference.signingRollout] beside a posture, and then the
  /// preference's value is what the client is at — which is why
  /// `selfRetrofit` reads
  /// [SigningRollout.defaultRetrofitAuthenticationAlgo] off the preference's
  /// stage rather than this getter. This one names the posture's own default,
  /// for an app comparing releases.
  SigningAlgoType get retrofitAuthenticationAlgo =>
      signingRollout.defaultRetrofitAuthenticationAlgo;

  /// The signing algorithms an enrollment keeps an active signing key for
  /// under this posture — **derived** from [signingRollout], never stored
  /// beside it.
  ///
  /// Two fields would be two controls over one behaviour, and the day they
  /// disagreed one of them would be a lie with no way to tell which. See
  /// [AtClientPreference.inUseSigningAlgorithms] for what naming an algorithm
  /// means and what an empty set leaves in place.
  Set<SigningAlgoType> get inUseSigningAlgorithms =>
      signingRollout.defaultInUseSigningAlgorithms;

  /// The 3.x defaults — the migration under way.
  ///
  /// Reads are fully post-quantum-capable; writes, enrollments and retrofits
  /// stay classical, so nothing this client produces outruns what the rest of
  /// the fleet can read. The envelope is not an axis here — there is one
  /// shape, emitted under every posture.
  ///
  /// [signingRollout] is [SigningRollout.now] for the same reason, so
  /// [inUseSigningAlgorithms] is empty: the enrollment holds no signing key of
  /// its own, its APKAM authentication key signs, and `_apsk` advertises that
  /// key as the bare public key string everything deployed can read.
  ///
  /// A deployment whose peers have all upgraded their readers states that by
  /// setting [SigningRollout.rollout1] beside this posture. ⚠️ **That does
  /// change what this client writes** — a rollout-1 enrollment authenticates
  /// with ML-DSA-65 and advertises a fresh RSA-2048 *signing* key in place of
  /// its authentication key. The advertisement stays the bare string, which is
  /// what makes it safe for un-upgraded peers, but it names a different key
  /// and the stage carries an atServer dependency (ML-DSA PKAM) that [now]
  /// does not.
  const ReleasePosture.migration()
      : writesPqByDefault = false,
        disallowLegacyEncryption = false,
        keyExchangeMode = EnrollmentKeyExchangeMode.legacy,
        signingRollout = SigningRollout.now;

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
  /// the rollout-1 **signing** key staying advertised as `retired` after it
  /// stops signing — a key is retained for what it signed, and this posture's
  /// predecessor signed with that one.
  const ReleasePosture.postQuantum()
      : writesPqByDefault = true,
        disallowLegacyEncryption = true,
        keyExchangeMode = EnrollmentKeyExchangeMode.pq,
        signingRollout = SigningRollout.rollout2;
}
