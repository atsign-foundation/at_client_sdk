import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart' show InvalidAtSignException;
import 'package:at_commons/atsign.dart';
import 'package:cryptography/cryptography.dart';

import 'passkey_port.dart';
import 'unlock_secret.dart';

/// The PRF eval input for every passkey: SHA-256 of `atsign:keys:lookup:v1`.
Future<Uint8List> recordPrfSalt() async {
  final hash = await Sha256().hash(utf8.encode('atsign:keys:lookup:v1'));
  return Uint8List.fromList(hash.bytes);
}

/// The record id and key encryption key derived from one passkey PRF output.
class RecordKeys {
  RecordKeys._(this.lookupHex, this.kek);

  /// 64 lowercase hex characters naming the record
  /// `public:_<lookupHex>.atkeysv@<atSign>`.
  final String lookupHex;

  /// The 32-byte AES-256-GCM key that seals the record.
  final Uint8List kek;

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// HKDF-SHA256 over [prf] with an empty salt and the labels
  /// `atkeys-record-id|<atSign>` and `atkeys-kek|<atSign>`, where the atSign
  /// is canonical (lowercase, leading `@`).
  ///
  /// Throws `InvalidAtSignException` when [atSign] is not an atSign.
  static Future<RecordKeys> derive(PrfSecret prf, String atSign) async {
    final canonical = atSign.toAtsign();
    final ikm = SecretKey(prf.output);
    Future<List<int>> expand(String label) async => (await _hkdf.deriveKey(
            secretKey: ikm,
            nonce: const [],
            info: utf8.encode('$label|$canonical')))
        .extractBytes();
    final lookup = await expand('atkeys-record-id');
    final kek = await expand('atkeys-kek');
    return RecordKeys._(
        lookup.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        Uint8List.fromList(kek));
  }
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

/// A registered passkey and its PRF output.
typedef PasskeyRegistration = ({Uint8List credentialId, PrfSecret secret});

/// An asserted passkey, its PRF output, and the canonical atSign in its
/// `userHandle`, or null when it carries none that is valid.
typedef PasskeyUnlock = ({
  Uint8List credentialId,
  PrfSecret secret,
  String? atSign,
});

String? _atSignFrom(Uint8List? userHandle) {
  if (userHandle == null) return null;
  try {
    return utf8.decode(userHandle).toAtsign();
  } on FormatException {
    return null;
  } on InvalidAtSignException {
    return null;
  }
}

/// A key encryption key (KEK) that leverages passkey PRF for secret derivation.
class PasskeyKek {
  /// Initializes the KEK with the given passkey [port].
  PasskeyKek(this.port);

  /// The passkey port used to perform ceremonies.
  final PasskeyPort port;

  /// Registers a passkey whose user is the canonical [atSign]; returns its id
  /// and PRF output.
  ///
  /// Throws [ArgumentError] when the canonical atSign exceeds the 64 UTF-8
  /// bytes WebAuthn allows in `user.id`.
  Future<PasskeyRegistration> register(String atSign) async {
    final canonical = atSign.toAtsign();
    if (utf8.encode(canonical).length > 64) {
      throw ArgumentError.value(
          atSign, 'atSign', 'longer than 64 UTF-8 bytes for a passkey user.id');
    }
    final result =
        await port.create(atSign: canonical, evalInput: await recordPrfSalt());
    return (
      credentialId: result.credentialId,
      secret: _secretFrom(result.prfFirst)
    );
  }

  /// Asserts and returns the PrfSecret; [credentialId] narrows allowCredentials.
  Future<PasskeyUnlock> unlock({Uint8List? credentialId}) async {
    final result = await port.get(
        evalInput: await recordPrfSalt(), allowCredential: credentialId);
    return (
      credentialId: result.credentialId,
      secret: _secretFrom(result.prfFirst),
      atSign: _atSignFrom(result.userHandle),
    );
  }
}
