import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';

/// Thrown by a [PasskeyPort] when a ceremony yields no credential: cancelled,
/// timed out, or no passkey matched.
class PasskeyCeremonyException extends AtException {
  PasskeyCeremonyException(super.message);

  @override
  String toString() => 'PasskeyCeremonyException: $message';
}

/// A registered passkey: its credential id and what the create ceremony said
/// about the `prf` extension: true when `prf.enabled` is true or
/// `prf.results.first` is present, false when `prf.enabled` is false, null
/// when the extension result is absent.
typedef PasskeyCreation = ({Uint8List credentialId, bool? prfEnabled});

/// A passkey assertion: its credential id and the PRF `first` result when
/// the authenticator returned one.
typedef PasskeyAssertion = ({Uint8List credentialId, Uint8List? prfFirst});

/// A WebAuthn ceremony pair: registering a passkey and asserting with one,
/// the assertion evaluating the `prf` extension with one input.
///
/// Both ceremonies throw [PasskeyCeremonyException] when they yield no
/// credential.
abstract class PasskeyPort {
  /// Registers a discoverable passkey for [atSign] and returns its credential
  /// id and the `prf` extension result. No PRF output is taken from
  /// registration: not every authenticator returns one there.
  Future<PasskeyCreation> create(
      {required String atSign,
      required DateTime enrolledAt,
      required String deviceName});

  /// Asserts with any discoverable passkey for this RP (or only
  /// [allowCredential] when given) and evaluates PRF with [evalInput].
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential});
}

/// A [PasskeyPort] that can tell the platform a passkey it holds is no longer
/// wanted.
///
/// Implemented by a port whose platform has such a call; a port without it
/// does not implement this. The call is a hint to the platform's passkey
/// manager, which may remove the passkey from its list. A page cannot delete
/// a passkey itself.
abstract class UnknownCredentialSignal {
  /// Tells the platform that [credentialId] is not known to this application.
  ///
  /// Throws when the platform has no such call or refuses it; callers treat
  /// that as the hint not being taken.
  Future<void> signalUnknownCredential(Uint8List credentialId);
}
