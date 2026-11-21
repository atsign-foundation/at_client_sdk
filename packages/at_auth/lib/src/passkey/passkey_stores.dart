import 'dart:typed_data';

/// The hints a device keeps per atSign beside the sealed @keys: the credential
/// id of the passkey that last unlocked them and the enrollment id of this
/// device's enrollment.
abstract class PasskeyHintStore {
  /// The remembered credential id of [atSign]'s passkey, or null when there
  /// is none.
  Future<Uint8List?> credentialId(String atSign);

  /// The remembered enrollment id of [atSign], or null when there is none.
  Future<String?> enrollmentId(String atSign);

  /// Replaces [atSign]'s credential id and enrollment id together: either
  /// both are stored or neither is.
  Future<void> putHint(
      String atSign, Uint8List credentialId, String enrollmentId);
}
