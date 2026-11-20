import 'dart:typed_data';

/// The credential id of the passkey that last unlocked an atSign's keys on
/// this device, kept beside the sealed @keys.
abstract class CredentialHintStore {
  Future<Uint8List?> credentialId(String atSign);
  Future<void> putCredentialId(String atSign, Uint8List id);
}

/// The enrollment id of this device's enrollment for an atSign, kept beside
/// the credential id.
abstract class EnrollmentIdStore {
  Future<String?> enrollmentId(String atSign);
  Future<void> putEnrollmentId(String atSign, String id);
}

/// A store of both hints that writes them together.
///
/// Implemented by a store that holds the credential id and the enrollment id
/// of an atSign in one place and can replace both in one atomic step. A
/// caller that finds its hint stores to be one [PasskeyHintStore] writes the
/// pair with [putHint]; a store that implements only [CredentialHintStore] and
/// [EnrollmentIdStore] is written with two separate puts.
abstract class PasskeyHintStore
    implements CredentialHintStore, EnrollmentIdStore {
  /// Replaces [atSign]'s credential id and enrollment id together: either
  /// both are stored or neither is.
  Future<void> putHint(
      String atSign, Uint8List credentialId, String enrollmentId);
}
