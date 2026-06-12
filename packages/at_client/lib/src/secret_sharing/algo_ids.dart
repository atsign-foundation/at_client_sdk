import 'package:meta/meta.dart' show experimental;

/// Registry of the algorithm identifiers used in client key bundles and
/// secret envelopes.
///
/// These ids exist for crypto agility: bundles advertise which algorithms a
/// client's published keys support, envelopes record which algorithms were
/// used to protect a payload, and readers ignore entries whose ids they do
/// not recognise. Adding a new suite later is just a matter of appending
/// new ids to the supported lists — no schema or protocol change.
@experimental
class SecretSharingAlgos {
  SecretSharingAlgos._();

  /// X-Wing hybrid post-quantum/traditional KEM
  /// (draft-connolly-cfrg-xwing-kem-10; X25519 + ML-KEM-768). The
  /// encapsulation ciphertext travels in the envelope's `encryptedKey`
  /// field and the encapsulated 32-byte shared secret is the content key.
  /// IND-CCA holds if either component survives, so confidentiality is
  /// harvest-now-decrypt-later resistant.
  static const String xWing = 'x-wing';

  /// AES-256-GCM authenticated encryption of the payload, keyed by the
  /// KEM shared secret, with a 12-byte nonce in the envelope's `iv` field.
  static const String aes256Gcm = 'aes-256-gcm';

  /// Key-establishment algorithms this client supports, strongest first.
  /// A sender picks the first of these that the recipient's bundle
  /// advertises.
  static const List<String> keyAlgos = [xWing];

  /// Payload-encryption algorithms this client supports, strongest first.
  static const List<String> encAlgos = [aes256Gcm];

  /// The `use` value for bundle keys whose purpose is establishing content
  /// keys (KEM encapsulation).
  static const String useEnc = 'enc';
}
