import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart' show SHA256HashingAlgo;

import 'prf_secret.dart';

/// HKDF info label for the record id. Every label has the form
/// `at_auth/custody/<name>/v1`; the info is `<label>|<canonical atSign>`.
const recordIdLabel = 'at_auth/custody/record-id/v1';

/// HKDF info label for the pointer namespace.
const recordNsLabel = 'at_auth/custody/ns/v1';

/// HKDF info label for the key that seals records.
const recordSealLabel = 'at_auth/custody/kek/v1';

/// HKDF info label for the seed of the enrollment's ML-DSA-65 APKAM signing
/// key.
const recordAuthSeedLabel = 'at_auth/custody/auth-seed/v1';

/// The PRF eval input for every passkey: SHA-256 of `atsign:keys:lookup:v1`.
Uint8List recordPrfSalt() {
  final hex = SHA256HashingAlgo().hash(utf8.encode('atsign:keys:lookup:v1'));
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16)
  ]);
}

/// Seals and opens record bodies under a key the caller never sees.
abstract class RecordSealer {
  /// [plaintext] sealed with [iv] and authenticated with [aad].
  Future<Uint8List> seal(Uint8List iv, List<int> plaintext, List<int> aad);

  /// The plaintext of [ciphertext].
  ///
  /// Throws `PasskeyRecordAuthenticationException` when it does not open.
  Future<Uint8List> open(Uint8List iv, Uint8List ciphertext, List<int> aad);

  /// Releases the key: drops a handle the implementation cannot read, or wipes
  /// bytes the implementation itself holds.
  void close();
}

/// The record id, pointer namespace, auth seed and record sealer derived from
/// one passkey PRF output.
///
/// [lookupHex] is 64 lowercase hex characters naming the record
/// `public:_<lookupHex>.<ns>@<atSign>`; [ns] is 64 lowercase hex characters
/// naming the namespace of this passkey's pointer. Both are public on the
/// wire. [authSeed] is the 32-byte seed of the enrollment's ML-DSA-65 APKAM
/// signing key.
typedef PasskeyDerivation = ({
  String lookupHex,
  String ns,
  Uint8List authSeed,
  RecordSealer sealer
});

/// Derives a [PasskeyDerivation] from a passkey PRF output.
abstract class PasskeyKeyDeriver {
  /// Derives from [prf] for the canonical [atSign] with HKDF-SHA256, an empty
  /// salt and the info `<label>|<atSign>` for each label above; zeroes
  /// the bytes of [prf] before returning. The sealer's key stays behind the
  /// [RecordSealer] port; this library never holds it as bytes.
  ///
  /// Throws [StateError] before deriving anything when [prf] was wiped, as
  /// reading [PrfSecret.output] does.
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign);
}
