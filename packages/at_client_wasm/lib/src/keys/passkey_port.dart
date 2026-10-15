import 'dart:typed_data';

/// Thrown by a [PasskeyPort] when a ceremony yields no credential: cancelled,
/// timed out, or no passkey matched.
class PasskeyCeremonyException implements Exception {
  PasskeyCeremonyException(this.message);

  final String message;

  @override
  String toString() => 'PasskeyCeremonyException: $message';
}

/// A WebAuthn ceremony that evaluates the `prf` extension with one input.
///
/// Both ceremonies throw [PasskeyCeremonyException] when they yield no
/// credential.
abstract interface class PasskeyPort {
  /// Registers a discoverable passkey for [atSign] and evaluates PRF with [evalInput].
  /// [prfFirst] is null when the chosen authenticator returned no PRF result.
  Future<({Uint8List credentialId, Uint8List? prfFirst})> create(
      {required String atSign, required Uint8List evalInput});

  /// Asserts with any passkey for this RP (or only [allowCredential] when given) and
  /// evaluates PRF with [evalInput].
  Future<({Uint8List credentialId, Uint8List? prfFirst})> get(
      {required Uint8List evalInput, Uint8List? allowCredential});
}
