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
  /// (draft-connolly-cfrg-xwing-kem-10; X25519 + ML-KEM-768). A key package's
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

  /// Key-establishment algorithms this client supports, strongest first.
  /// A sender picks the first of these that the recipient's key package
  /// advertises.
  static const List<String> keyAlgos = [xWing];

  /// Sealing suites this client can produce and open, strongest first.
  static const List<String> suites = [xWingHpke];

  /// The `use` value for key-package keys whose purpose is establishing
  /// content keys (KEM encapsulation).
  static const String useEnc = 'enc';
}
