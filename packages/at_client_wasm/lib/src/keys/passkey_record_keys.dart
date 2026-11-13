import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart' show HkdfSha256;
import 'package:at_commons/atsign.dart';
import 'package:cryptography/cryptography.dart';

import 'passkey_port.dart';
import 'prf_support.dart';
import 'unlock_secret.dart';

export 'prf_support.dart' show PrfUnavailableException;

/// The PRF eval input for every passkey: SHA-256 of `atsign:keys:lookup:v1`.
Future<Uint8List> recordPrfSalt() async {
  final hash = await Sha256().hash(utf8.encode('atsign:keys:lookup:v1'));
  return Uint8List.fromList(hash.bytes);
}

/// The record id, key encryption key and auth seed derived from one passkey
/// PRF output.
class RecordKeys {
  RecordKeys._(this.lookupHex, this.kek, this.authSeed);

  /// 64 lowercase hex characters naming the record
  /// `public:_<lookupHex>.atkeysv@<atSign>`.
  final String lookupHex;

  /// The 32-byte AES-256-GCM key that seals the record.
  final Uint8List kek;

  /// The 32-byte seed of the enrollment's ML-DSA-65 APKAM signing key.
  final Uint8List authSeed;

  /// HKDF-SHA256 over [prf] with an empty salt and the labels
  /// `atkeys-record-id|<atSign>`, `atkeys-kek|<atSign>` and
  /// `at_auth/custody/auth-seed/v1|<atSign>`, where the atSign is canonical
  /// (lowercase, leading `@`).
  ///
  /// Throws `InvalidAtSignException` when [atSign] is not an atSign.
  static Future<RecordKeys> derive(PrfSecret prf, String atSign) async {
    final canonical = atSign.toAtsign();
    Uint8List expand(String label) => HkdfSha256.deriveKey(prf.output,
        info: utf8.encode('$label|$canonical'), length: 32);
    final lookup = expand('atkeys-record-id');
    return RecordKeys._(
        lookup.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        expand('atkeys-kek'),
        expand('at_auth/custody/auth-seed/v1'));
  }
}

PrfSecret _secretFrom(Uint8List? prfFirst, PrfSupport? support) {
  if (prfFirst == null) {
    support?.recordMiss();
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

/// An asserted passkey and its PRF output.
typedef PasskeyUnlock = ({Uint8List credentialId, PrfSecret secret});

/// A key encryption key (KEK) that leverages passkey PRF for secret derivation.
class PasskeyKek {
  /// Initializes the KEK with the given passkey [port] and, optionally, the
  /// [prfSupport] check that refuses setup before any ceremony.
  PasskeyKek(this.port, {this.prfSupport});

  /// The passkey port used to perform ceremonies.
  final PasskeyPort port;

  /// The PRF support check, or null to attempt every ceremony.
  final PrfSupport? prfSupport;

  /// Registers a passkey whose user is the canonical [atSign]; returns its id
  /// and the PRF output of an assertion with it.
  ///
  /// Throws [PrfUnavailableException] before any ceremony when PRF is known
  /// to be unsupported.
  Future<PasskeyRegistration> register(String atSign) async {
    await prfSupport?.require();
    final credentialId = await port.create(atSign: atSign.toAtsign());
    final assertion = await port.get(
        evalInput: await recordPrfSalt(), allowCredential: credentialId);
    return (
      credentialId: credentialId,
      secret: _secretFrom(assertion.prfFirst, prfSupport)
    );
  }

  /// Asserts and returns the PrfSecret; [credentialId] narrows allowCredentials.
  Future<PasskeyUnlock> unlock({Uint8List? credentialId}) async {
    final result = await port.get(
        evalInput: await recordPrfSalt(), allowCredential: credentialId);
    return (
      credentialId: result.credentialId,
      secret: _secretFrom(result.prfFirst, prfSupport),
    );
  }
}
