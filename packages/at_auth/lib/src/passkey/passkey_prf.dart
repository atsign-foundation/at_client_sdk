import 'dart:async';
import 'dart:typed_data';

import 'package:at_commons/atsign.dart';

import 'passkey_derivation.dart';
import 'passkey_port.dart';
import 'prf_support.dart';
import 'prf_secret.dart';

export 'prf_support.dart' show PrfUnavailableException;

const _unusablePrf = 'The authenticator did not return a usable PRF result';

PrfSecret _secretFrom(Uint8List? prfFirst) {
  if (prfFirst == null) throw PrfUnavailableException(_unusablePrf);
  try {
    return PrfSecret(prfFirst);
  } on ArgumentError {
    prfFirst.fillRange(0, prfFirst.length, 0);
    throw PrfUnavailableException(_unusablePrf);
  }
}

/// A registered passkey and its PRF output. The caller wipes [secret] after
/// use.
typedef PasskeyRegistration = ({Uint8List credentialId, PrfSecret secret});

/// An asserted passkey and its PRF output. The caller wipes [secret] after
/// use.
typedef PasskeyUnlock = ({Uint8List credentialId, PrfSecret secret});

/// The passkey ceremonies that yield a PRF output.
class PasskeyPrf {
  /// Initializes the ceremonies with the given passkey [port] and, optionally, the
  /// [prfSupport] check that refuses setup before any ceremony.
  PasskeyPrf(this.port, {this.prfSupport});

  /// The passkey port used to perform ceremonies.
  final PasskeyPort port;

  /// The PRF support check, or null to attempt every ceremony.
  final PrfSupport? prfSupport;

  /// Registers a passkey whose user is the canonical [atSign]; returns its id
  /// and the PRF output of an assertion with it.
  ///
  /// Throws [PrfUnavailableException] before any ceremony when PRF is known
  /// to be unsupported, and after both ceremonies when the PRF output that
  /// came back is missing, not 32 bytes, or all zeroes. When the assertion
  /// after a successful create throws or yields no usable PRF output, the
  /// created passkey is reported through [signalUnknownCredential] and the
  /// failure propagates at once, without waiting for the platform to take the
  /// report. A miss is recorded only when the create ceremony did not report
  /// PRF enabled and the assertion returned no PRF output; a failed ceremony
  /// records nothing.
  Future<PasskeyRegistration> register(String atSign,
      {required DateTime enrolledAt, required String deviceName}) async {
    await prfSupport?.require();
    final creation = await port.create(
        atSign: atSign.toAtsign(),
        enrolledAt: enrolledAt,
        deviceName: deviceName);
    try {
      final assertion = await port.get(
          evalInput: recordPrfSalt(), allowCredential: creation.credentialId);
      if (assertion.prfFirst == null && creation.prfEnabled != true) {
        prfSupport?.recordMiss();
      }
      return (
        credentialId: creation.credentialId,
        secret: _secretFrom(assertion.prfFirst)
      );
    } on Object {
      unawaited(signalUnknownCredential(creation.credentialId));
      rethrow;
    }
  }

  /// Asserts and returns the PRF output; [credentialId] narrows the allowed
  /// credentials. Never records a PRF miss.
  Future<PasskeyUnlock> unlock({Uint8List? credentialId}) async {
    final result = await port.get(
        evalInput: recordPrfSalt(), allowCredential: credentialId);
    return (
      credentialId: result.credentialId,
      secret: _secretFrom(result.prfFirst),
    );
  }

  /// Tells the platform, when [port] is an [UnknownCredentialSignal], that
  /// [credentialId] is not wanted. A failure to signal is ignored: the
  /// passkey stays in the platform's list.
  Future<void> signalUnknownCredential(Uint8List credentialId) async {
    if (port case final UnknownCredentialSignal signal) {
      try {
        await signal.signalUnknownCredential(credentialId);
      } on Object {
        // A hint only; nothing to do when the platform does not take it.
      }
    }
  }
}
