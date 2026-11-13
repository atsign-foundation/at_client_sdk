import 'dart:typed_data';

/// Thrown by a [PasskeyPort] when a ceremony yields no credential: cancelled,
/// timed out, or no passkey matched.
class PasskeyCeremonyException implements Exception {
  PasskeyCeremonyException(this.message);

  final String message;

  @override
  String toString() => 'PasskeyCeremonyException: $message';
}

/// A passkey assertion: its credential id and the PRF `first` result when
/// the authenticator returned one.
typedef PasskeyAssertion = ({Uint8List credentialId, Uint8List? prfFirst});

/// A WebAuthn ceremony pair: registering a passkey and asserting with one,
/// the assertion evaluating the `prf` extension with one input.
///
/// Both ceremonies throw [PasskeyCeremonyException] when they yield no
/// credential.
abstract interface class PasskeyPort {
  /// Registers a discoverable passkey for [atSign] and returns its credential
  /// id. No PRF result is taken from registration: not every authenticator
  /// returns one there.
  Future<Uint8List> create({required String atSign});

  /// Asserts with any discoverable passkey for this RP (or only
  /// [allowCredential] when given) and evaluates PRF with [evalInput].
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential});
}
