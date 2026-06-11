/// Registry of the algorithm identifiers used in client key bundles and
/// secret envelopes.
///
/// These ids exist for crypto agility: bundles advertise which algorithms a
/// client's published keys support, envelopes record which algorithms were
/// used to protect a payload, and readers ignore entries whose ids they do
/// not recognise. Adding a stronger suite later (e.g. the X-Wing hybrid
/// post-quantum KEM and an AEAD cipher) is then just a matter of appending
/// new ids to the supported lists — no schema or protocol change.
class SecretSharingAlgos {
  SecretSharingAlgos._();

  /// RSA-2048 key transport: the content key is encrypted to the recipient's
  /// published RSA public key (the same primitive the SDK uses for
  /// cross-atSign shared-key distribution).
  static const String rsa2048 = 'rsa-2048';

  /// AES-256 in CTR mode (the SDK's standard value cipher). CTR provides no
  /// integrity by itself; envelopes carry an APKAM signature over the
  /// ciphertext which must be verified before decrypting.
  static const String aes256Ctr = 'aes-256-ctr';

  /// Key-protection algorithms this client supports, strongest first.
  /// A sender picks the first of these that the recipient's bundle
  /// advertises.
  static const List<String> keyAlgos = [rsa2048];

  /// Payload-encryption algorithms this client supports, strongest first.
  static const List<String> encAlgos = [aes256Ctr];

  /// The `use` value for bundle keys whose purpose is protecting content
  /// keys (key transport today, KEM encapsulation later).
  static const String useEnc = 'enc';
}
