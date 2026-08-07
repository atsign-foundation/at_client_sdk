import 'package:at_auth/at_auth.dart' show KeyAlgorithmType;
import 'package:at_chops/at_chops.dart'
    show AtKemAlgorithm, MlKem1024PureDartAlgo, XWingPureDartAlgo;
import 'package:meta/meta.dart' show experimental;

/// Registry of the algorithm identifiers used in per-APKAM key packages and
/// secret envelopes.
///
/// These ids exist for crypto agility: a key package advertises which
/// algorithms its X-Wing public key supports, envelopes record which
/// algorithms were used to protect a payload, and readers ignore entries
/// whose ids they do not recognise. Adding a new suite later is just a matter
/// of appending new ids to the supported lists — no schema or protocol change.
@experimental
class SecretSharingAlgos {
  SecretSharingAlgos._();

  /// X-Wing hybrid post-quantum/traditional KEM
  /// (IANA HPKE KEM id `0x647A`; X25519 + ML-KEM-768). A key package's
  /// advertised key is an X-Wing public key; a sender encapsulates to it.
  /// IND-CCA holds if either component survives, so confidentiality is
  /// harvest-now-decrypt-later resistant.
  static const String xWing = 'x-wing';

  /// HPKE-style sealing suite — X-Wing KEM + HKDF-SHA256 + AES-256-GCM, as
  /// implemented by at_chops `pqSeal`/`pqOpen`. The envelope's `sealed`
  /// field carries the whole construction (KEM ciphertext, the HKDF-derived
  /// AEAD key schedule, authenticated ciphertext and tag); the envelope's
  /// `suite` field records which construction produced it.
  static const String xWingHpke = 'x-wing-hpke-v1';

  /// Pure ML-KEM-1024 (FIPS 203), IANA HPKE KEM id `0x0042` — the **no-hybrid**
  /// option.
  ///
  /// Chosen for its citation rather than its strength: used alone it is the
  /// only key establishment here whose specification chain contains no draft,
  /// where every hybrid has its combiner specified only in an IETF draft. It is
  /// also CNSA 2.0's mandated parameter set, and CNSA 2.0 treats hybrids as
  /// non-compliant.
  ///
  /// What it gives up is the hedge against ML-KEM falling to *classical*
  /// cryptanalysis. It loses nothing against a quantum adversary, since a
  /// hybrid's traditional half is Shor-broken anyway.
  static const String mlKem1024 = 'ml-kem-1024';

  /// RFC 9180 HPKE Base mode over [xWing]: KEM `0x647A`, KDF HKDF-SHA256,
  /// AEAD ChaCha20-Poly1305. `pqSeal` version `0x02`.
  ///
  /// ChaCha rather than AES-GCM because it is the only AEAD the HPKE working
  /// group publishes `0x647A` vectors for.
  static const String xWingRfc9180 = 'x-wing-rfc9180-v1';

  /// RFC 9180 HPKE Base mode over [mlKem1024]: KEM `0x0042`, KDF HKDF-SHA384,
  /// AEAD AES-256-GCM. `pqSeal` version `0x03`.
  static const String mlKem1024Rfc9180 = 'ml-kem-1024-rfc9180-v1';

  /// Key-establishment algorithms this client supports, strongest first.
  /// A sender picks the first of these that the recipient's key package
  /// advertises.
  ///
  /// Ordering is a *sender* preference over what a recipient offers, not a
  /// judgement that one is stronger — the two are chosen for different
  /// reasons, and which an atSign advertises is its own configuration.
  static const List<String> keyAlgos = [xWing, mlKem1024];

  /// Sealing suites this client can produce and open, strongest first.
  static const List<String> suites = [
    xWingRfc9180,
    mlKem1024Rfc9180,
    xWingHpke,
  ];

  /// The `pqSeal` envelope version a suite maps to.
  ///
  /// The version byte names the whole suite on the wire, so this is the only
  /// place the two vocabularies meet. An unknown suite returns null rather than
  /// defaulting: sealing under a guessed construction produces a record the
  /// recipient cannot open, and the failure would surface on their side.
  static int? sealVersionFor(String suite) => switch (suite) {
        xWingHpke => 0x01,
        xWingRfc9180 => 0x02,
        mlKem1024Rfc9180 => 0x03,
        _ => null,
      };

  /// The sealing suite that goes with a key-establishment algorithm.
  ///
  /// The KEM fixes the suite: nothing can seal ML-KEM-1024 to an X-Wing
  /// encapsulation key or the reverse, so a recipient's advertised `alg` is
  /// what decides which construction a sender uses.
  ///
  /// This is the *preferred* suite for that KEM — what a sender picks when it
  /// has a free choice. [openableSuitesFor] is the wider set the same key can
  /// unwrap, which is what a holder advertises.
  static String? suiteForKeyAlgo(String keyAlgo) => switch (keyAlgo) {
        xWing => xWingRfc9180,
        mlKem1024 => mlKem1024Rfc9180,
        _ => null,
      };

  /// Every suite a holder of a [keyAlgo] key can **open**, in [suites] order.
  ///
  /// Wider than [suiteForKeyAlgo] because a KEM key opens every construction
  /// built on that KEM, not only the one a sender would choose: an X-Wing
  /// private unwraps both the RFC 9180 suite and the original `atPQv1-base`
  /// one, since the difference between them is the key schedule and the AEAD,
  /// not the decapsulation.
  ///
  /// An unrecognised [keyAlgo] yields nothing rather than everything. A holder
  /// must never claim a suite on the strength of a key this build cannot
  /// identify — the claim would be acted on by a sender, and the failure would
  /// arrive on the holder's side as an AEAD error.
  static List<String> openableSuitesFor(String keyAlgo) => switch (keyAlgo) {
        xWing => const [xWingRfc9180, xWingHpke],
        mlKem1024 => const [mlKem1024Rfc9180],
        _ => const [],
      };

  /// The suites a holder advertising [keyAlgos] can open, deduplicated and in
  /// [suites] order (strongest first).
  ///
  /// This is what a key package's `suites` field must be derived from. Stating
  /// the build's whole [suites] list instead would claim, on behalf of a holder
  /// that advertises one KEM, that it can open constructions built on the
  /// other — and nothing it holds can.
  static List<String> openableSuitesForAll(Iterable<String> keyAlgos) {
    final openable = keyAlgos.expand(openableSuitesFor).toSet();
    return [
      for (final suite in suites)
        if (openable.contains(suite)) suite
    ];
  }

  /// The KEM implementation a key-establishment algorithm id names.
  ///
  /// Pure-Dart backends specifically. The FFI ones return an opaque
  /// process-lifetime handle as an ML-KEM secret key, and every key reached
  /// through here has to survive a restart.
  ///
  /// Null for an id this build does not implement, so a caller cannot guess:
  /// encapsulating under the wrong KEM produces a record the recipient can
  /// never open, and the failure would surface on their side as an AEAD error
  /// with nothing to point at.
  static AtKemAlgorithm? kemFor(String keyAlgo) => switch (keyAlgo) {
        xWing => XWingPureDartAlgo.instance,
        mlKem1024 => MlKem1024PureDartAlgo.instance,
        _ => null,
      };

  /// The KEM that opens an envelope produced under [suite].
  ///
  /// The receive path's counterpart to [kemFor]: `pqOpen` reads the version
  /// byte itself, but the KEM instance is the caller's to supply, and an
  /// envelope sealed under one KEM handed to the other fails as an
  /// indistinguishable AEAD error. Both X-Wing suites map to the same KEM —
  /// they differ in key schedule and AEAD, not in decapsulation.
  static AtKemAlgorithm? kemForSuite(String suite) => switch (suite) {
        xWingHpke || xWingRfc9180 => XWingPureDartAlgo.instance,
        mlKem1024Rfc9180 => MlKem1024PureDartAlgo.instance,
        _ => null,
      };

  /// The `AtKeysMaterial.keyAlgorithmType` token a keyfile names [keyAlgo] by.
  ///
  /// A keyfile has its own vocabulary — `xwing`, `mlkem1024` — deliberately
  /// shared with the pkam/enrollment `signingAlgo` literals rather than with
  /// these protocol ids. This and [keyAlgoForMaterial] are the only places the
  /// two meet.
  static String? materialAlgoFor(String keyAlgo) => switch (keyAlgo) {
        xWing => KeyAlgorithmType.xWing,
        mlKem1024 => KeyAlgorithmType.mlKem1024,
        _ => null,
      };

  /// The protocol id for a keyfile's `keyAlgorithmType` token, or null if this
  /// build does not know that token.
  ///
  /// Null is how a key-package lookup tells a key it can use from one it
  /// cannot: `keyAlgorithmType` is an open string by contract — a keyfile
  /// written by a newer client round-trips values this build has never seen —
  /// so an unknown token means "not mine", not "malformed".
  static String? keyAlgoForMaterial(String materialAlgo) =>
      switch (materialAlgo) {
        KeyAlgorithmType.xWing => xWing,
        KeyAlgorithmType.mlKem1024 => mlKem1024,
        _ => null,
      };

  /// The `use` value for key-package keys whose purpose is establishing
  /// content keys (KEM encapsulation).
  static const String useEnc = 'enc';
}
