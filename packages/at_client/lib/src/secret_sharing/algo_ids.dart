import 'package:at_auth/at_auth.dart' show CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart'
    show AtKemAlgorithm, MlKem1024PureDartAlgo, XWingPureDartAlgo;
import 'package:meta/meta.dart' show experimental;

/// Registry of the algorithm identifiers used in per-APKAM key packages and
/// secret envelopes.
///
/// These ids exist for crypto agility: a key package advertises which
/// algorithms its enc public key supports, envelopes record which
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

  /// Pure ML-KEM-1024 (FIPS 203), IANA HPKE KEM id `0x0042` — the **no-hybrid**
  /// option, and CNSA 2.0's mandated parameter set.
  ///
  /// Used alone it carries no hedge against ML-KEM falling to *classical*
  /// cryptanalysis; against a quantum adversary it loses nothing, since a
  /// hybrid's traditional half is Shor-broken anyway.
  static const String mlKem1024 = 'ml-kem-1024';

  /// RFC 9180 HPKE Base mode over [xWing]: KEM `0x647A`, KDF HKDF-SHA256,
  /// AEAD ChaCha20-Poly1305. `pqSeal` version `0x02`.
  static const String xWingRfc9180 = 'x-wing-rfc9180-v1';

  /// RFC 9180 HPKE Base mode over [mlKem1024]: KEM `0x0042`, KDF HKDF-SHA384,
  /// AEAD AES-256-GCM. `pqSeal` version `0x03`.
  static const String mlKem1024Rfc9180 = 'ml-kem-1024-rfc9180-v1';

  /// Key-establishment algorithms this client supports, strongest first.
  /// A sender picks the first of these that the recipient's key package
  /// advertises.
  ///
  /// The order is a *sender* preference over what a recipient offers; which
  /// algorithms an atSign advertises is its own configuration.
  static const List<String> keyAlgos = [xWing, mlKem1024];

  /// Sealing suites this client can produce and open, strongest first.
  static const List<String> suites = [
    xWingRfc9180,
    mlKem1024Rfc9180,
  ];

  /// The `pqSeal` envelope version a suite maps to.
  ///
  /// Null for a suite this build does not know, rather than a default: sealing
  /// under a guessed construction produces a record the recipient cannot open,
  /// and the failure surfaces on their side.
  static int? sealVersionFor(String suite) => switch (suite) {
        xWingRfc9180 => 0x02,
        mlKem1024Rfc9180 => 0x03,
        _ => null,
      };

  /// The preferred sealing suite for a key-establishment algorithm, or null
  /// for an id this build does not implement.
  ///
  /// This is what a sender picks when it has a free choice;
  /// [openableSuitesFor] is the wider set the same key can unwrap, which is
  /// what a holder advertises.
  static String? suiteForKeyAlgo(String keyAlgo) => switch (keyAlgo) {
        xWing => xWingRfc9180,
        mlKem1024 => mlKem1024Rfc9180,
        _ => null,
      };

  /// The construction two parties settle on: the first of [senderSuites] that
  /// [recipientSuites] also declares, or null when they share none.
  ///
  /// The sender's list is the preference order; the recipient's is only a
  /// membership test. Every negotiation goes through here, so that the same
  /// pair of parties agrees on one construction whichever substrate is asking.
  static String? bestSuiteBetween(
      List<String> senderSuites, List<String> recipientSuites) {
    for (final suite in senderSuites) {
      if (recipientSuites.contains(suite)) return suite;
    }
    return null;
  }

  /// Every suite a holder of a [keyAlgo] key can **open**, in [suites] order.
  ///
  /// An advertisement list, not a sender's preference order: narrowing what a
  /// sender will emit must not narrow this. An unrecognised [keyAlgo] yields
  /// nothing rather than everything, so a holder never claims a suite on the
  /// strength of a key this build cannot identify.
  static List<String> openableSuitesFor(String keyAlgo) => switch (keyAlgo) {
        xWing => const [xWingRfc9180],
        mlKem1024 => const [mlKem1024Rfc9180],
        _ => const [],
      };

  /// The suites a holder advertising [keyAlgos] can open, deduplicated and in
  /// [suites] order (strongest first).
  ///
  /// A key package's `suites` field is derived from this rather than from the
  /// build's whole [suites] list: a holder advertising one KEM cannot open
  /// constructions built on the other.
  static List<String> openableSuitesForAll(Iterable<String> keyAlgos) {
    final openable = keyAlgos.expand(openableSuitesFor).toSet();
    return [
      for (final suite in suites)
        if (openable.contains(suite)) suite
    ];
  }

  /// The pure-Dart KEM implementation a key-establishment algorithm id names,
  /// or null for an id this build does not implement.
  ///
  /// Pure Dart because the FFI backends return an opaque process-lifetime
  /// handle as an ML-KEM secret key, and every key reached through here has to
  /// survive a restart.
  static AtKemAlgorithm? kemFor(String keyAlgo) => switch (keyAlgo) {
        xWing => XWingPureDartAlgo.instance,
        mlKem1024 => MlKem1024PureDartAlgo.instance,
        _ => null,
      };

  /// The public key length [keyAlgo] requires, or null for an id this build
  /// does not implement.
  ///
  /// Callers need it because a key id proves nothing about length: it is the
  /// digest of whatever bytes are carried, so it matches a forged key as
  /// readily as a real one. Must stay in step with [kemFor].
  static int? publicKeyLengthFor(String keyAlgo) => switch (keyAlgo) {
        xWing => XWingPureDartAlgo.publicKeyLength,
        mlKem1024 => MlKem1024PureDartAlgo.publicKeyLength,
        _ => null,
      };

  /// The KEM that opens an envelope produced under [suite], or null for a
  /// suite this build does not implement.
  ///
  /// `pqOpen` reads the version byte itself, but the KEM instance is the
  /// caller's to supply, and an envelope sealed under one KEM handed to the
  /// other fails as an indistinguishable AEAD error.
  static AtKemAlgorithm? kemForSuite(String suite) => switch (suite) {
        xWingRfc9180 => XWingPureDartAlgo.instance,
        mlKem1024Rfc9180 => MlKem1024PureDartAlgo.instance,
        _ => null,
      };

  /// The `CryptographicMaterial.algorithm` token a keyfile names [keyAlgo] by,
  /// or null for an id this build does not implement.
  ///
  /// A keyfile has its own vocabulary, shared with the pkam/enrollment
  /// `signingAlgo` literals rather than with these protocol ids; this and
  /// [keyAlgoForMaterial] are the only places the two meet.
  static CryptographicMaterialAlgorithm? materialAlgoFor(String keyAlgo) =>
      switch (keyAlgo) {
        xWing => CryptographicMaterialAlgorithm.xWing,
        mlKem1024 => CryptographicMaterialAlgorithm.mlKem1024,
        _ => null,
      };

  /// The protocol id for a keyfile's `algorithm` token, or null if this
  /// build does not know that token.
  ///
  /// `algorithm` is an open string by contract, so an unknown token means
  /// "not mine", not "malformed" — null is how a key-package lookup tells a
  /// key it can use from one it cannot.
  static String? keyAlgoForMaterial(
          CryptographicMaterialAlgorithm materialAlgo) =>
      switch (materialAlgo) {
        CryptographicMaterialAlgorithm.xWing => xWing,
        CryptographicMaterialAlgorithm.mlKem1024 => mlKem1024,
        _ => null,
      };

  /// The `use` value for key-package keys whose purpose is establishing
  /// content keys (KEM encapsulation).
  static const String useEnc = 'enc';
}
