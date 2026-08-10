import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart'
    show jwsEnvelopeVersion, signedEnvelopeVersion;

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
/// - **The signed-envelope wrapper a signer emits** — [envelopeVersion],
///   consulted by `EnvelopeSigning` when no version was set on the signer
///   instance. Readers accept both shapes regardless.
/// - **How an enrollment's `apkamSymmetricKey` travels** — [keyExchangeMode].
///   Enrollment submission goes through `package:at_auth`, which cannot see a
///   preference, so this value is applied by whoever builds the
///   `AtEnrollmentRequest` — and pq mode needs its two companions built
///   alongside (`enrollmentKeyPackageBuilder`, the symmetric-key resolver),
///   exactly as the request's own documentation describes.
/// - **What a self-retrofit mints** — [retrofitSigningAlgo], the default for
///   `selfRetrofit`'s `signingAlgo` parameter. An explicit argument wins.
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

  /// The signed-envelope wrapper version a signer emits when none was set on
  /// the instance: `signedEnvelopeVersion` (1) or `jwsEnvelopeVersion` (2).
  final int envelopeVersion;

  /// The key-exchange mode an enrollment submission built under this posture
  /// uses. See `EnrollmentKeyExchangeMode` for what pq mode requires.
  final EnrollmentKeyExchangeMode keyExchangeMode;

  /// The signing algorithm `selfRetrofit` mints when the caller names none.
  final SigningAlgoType retrofitSigningAlgo;

  /// The 3.x defaults — the migration under way.
  ///
  /// Reads are fully post-quantum-capable; writes, envelopes, enrollments and
  /// retrofits stay classical, so nothing this client produces outruns what
  /// the rest of the fleet can read.
  const ReleasePosture.migration()
      : writesPqByDefault = false,
        disallowLegacyEncryption = false,
        envelopeVersion = signedEnvelopeVersion,
        keyExchangeMode = EnrollmentKeyExchangeMode.legacy,
        retrofitSigningAlgo = SigningAlgoType.rsa2048;

  /// The 4.0 defaults — post-quantum by default.
  ///
  /// New data is written under the nskey data path, legacy writes are
  /// refused, envelopes go out in the JWS shape, enrollments exchange their
  /// symmetric key post-quantum, and a retrofit mints ML-DSA.
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
  /// The readers for everything this posture emits — nskey records, JWS
  /// envelopes — ship in the **same release line as the posture itself**, so
  /// its peers must be on at least that release, not merely "any 3.x".
  const ReleasePosture.postQuantum()
      : writesPqByDefault = true,
        disallowLegacyEncryption = true,
        envelopeVersion = jwsEnvelopeVersion,
        keyExchangeMode = EnrollmentKeyExchangeMode.pq,
        retrofitSigningAlgo = SigningAlgoType.mldsa65;
}
