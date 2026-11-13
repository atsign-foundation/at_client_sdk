import 'dart:typed_data';

/// Thrown by a [PasskeyPort] when a ceremony yields no credential: cancelled,
/// timed out, or no passkey matched.
class PasskeyCeremonyException implements Exception {
  PasskeyCeremonyException(this.message);

  final String message;

  @override
  String toString() => 'PasskeyCeremonyException: $message';
}

/// A passkey assertion: its credential id, the PRF `first` result when the
/// authenticator returned one, and its `userHandle` when present.
typedef PasskeyAssertion = ({
  Uint8List credentialId,
  Uint8List? prfFirst,
  Uint8List? userHandle,
});

/// A WebAuthn ceremony that evaluates the `prf` extension with one input.
///
/// Both ceremonies throw [PasskeyCeremonyException] when they yield no
/// credential.
abstract interface class PasskeyPort {
  /// Registers a discoverable passkey for [atSign] and evaluates PRF with [evalInput].
  /// [prfFirst] is null when the chosen authenticator returned no PRF result.
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput});

  /// Asserts with any discoverable passkey for this RP (or only
  /// [allowCredential] when given) and evaluates PRF with [evalInput].
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential});
}
