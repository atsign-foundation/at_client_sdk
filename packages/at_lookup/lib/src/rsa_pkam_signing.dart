import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';

/// Signs [message] with the DER-encoded PKAM [secretKey] using RSA.
///
/// [RsaSigningAlgo] pins its key size at construction and
/// [RsaSigningAlgo.signBytes] throws [AtSigningException] for a key whose
/// modulus is not that size, so this tries every size the Atsign Protocol's
/// [SigningAlgoType] defines for RSA and only fails once none of them sign —
/// mirroring how `AtLookupImpl._verifyRsaSignature` handles a peer's public
/// key whose size it does not control. The privateKey ladder
/// (`AtLookupImpl.authenticate`) and `MonitorClient` both accept a
/// caller-supplied PKAM private key whose modulus size they do not control
/// either, so both call this rather than pinning one size.
Future<Uint8List> signRsaPkam(Uint8List message, Uint8List secretKey,
    {HashingAlgoType hashingAlgoType = HashingAlgoType.sha256}) async {
  AtSigningException? lastFailure;
  for (final keySize in [2048, 4096]) {
    try {
      return await RsaSigningAlgo(
              hashingAlgoType: hashingAlgoType, keySize: keySize)
          .signBytes(message, secretKey: secretKey);
    } on AtSigningException catch (e) {
      lastFailure = e;
    }
  }
  throw lastFailure!;
}
