import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'passkey_port.dart';
import 'unlock_secret.dart';

/// The PRF eval input for [atSign]: SHA-256 of
/// `at_client_wasm/prf-eval/v1|<atSign>`.
Future<Uint8List> prfEvalInput(String atSign) async {
  final hash =
      await Sha256().hash(utf8.encode('at_client_wasm/prf-eval/v1|$atSign'));
  return Uint8List.fromList(hash.bytes);
}

/// Thrown when the authenticator does not support or return a valid PRF result.
class PrfUnavailableException implements Exception {
  /// Initializes the exception with an error [message].
  PrfUnavailableException(this.message);

  /// The error message.
  final String message;

  /// Returns a string representation of this exception.
  @override
  String toString() => 'PrfUnavailableException: $message';
}

PrfSecret _secretFrom(Uint8List? prfFirst) {
  if (prfFirst == null) {
    throw PrfUnavailableException('Authenticator did not return a PRF result');
  }
  try {
    return PrfSecret(prfFirst);
  } on ArgumentError catch (e) {
    throw PrfUnavailableException(e.message);
  }
}

/// A key encryption key (KEK) that leverages passkey PRF for secret derivation.
class PasskeyKek {
  /// Initializes the KEK with the given passkey [port].
  PasskeyKek(this.port);

  /// The passkey port used to perform ceremonies.
  final PasskeyPort port;

  /// Registers a passkey; returns its id and the PrfSecret for the new `prf` unlock.
  Future<({Uint8List credentialId, PrfSecret secret})> register(
      String atSign) async {
    final evalInput = await prfEvalInput(atSign);
    final result = await port.create(atSign: atSign, evalInput: evalInput);
    return (
      credentialId: result.credentialId,
      secret: _secretFrom(result.prfFirst)
    );
  }

  /// Asserts and returns the PrfSecret; [credentialId] narrows allowCredentials.
  Future<({Uint8List credentialId, PrfSecret secret})> unlock(String atSign,
      {Uint8List? credentialId}) async {
    final evalInput = await prfEvalInput(atSign);
    final result =
        await port.get(evalInput: evalInput, allowCredential: credentialId);
    return (
      credentialId: result.credentialId,
      secret: _secretFrom(result.prfFirst)
    );
  }
}
