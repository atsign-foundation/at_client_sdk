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
  static String? suiteForKeyAlgo(String keyAlgo) => switch (keyAlgo) {
        xWing => xWingRfc9180,
        mlKem1024 => mlKem1024Rfc9180,
        _ => null,
      };

  /// The `use` value for key-package keys whose purpose is establishing
  /// content keys (KEM encapsulation).
  static const String useEnc = 'enc';
}
