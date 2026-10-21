import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/src/rsa_pkam_signing.dart';
import 'package:test/test.dart';

/// [signRsaPkam] backs both PKAM-signing call sites that accept a
/// caller-supplied private key whose modulus size is not known ahead of
/// time: the privateKey ladder in `AtLookupImpl.authenticate` and
/// `MonitorClient`. A single [RsaSigningAlgo] instance pins its key size at
/// construction and throws [AtSigningException] for a key of the wrong size,
/// so these tests pin that [signRsaPkam] picks the right size for a
/// 2048-bit key and a 4096-bit key, rather than only ever trying the first
/// size and throwing for the other.
void main() {
  final message = Uint8List.fromList(utf8.encode('from challenge bytes'));

  for (final keySize in [2048, 4096]) {
    test('a $keySize-bit key signs and the signature verifies', () async {
      final keyPair = await RsaSigningAlgo(keySize: keySize).generateKeyPair();

      final signature = await signRsaPkam(message, keyPair.secretKey);

      await RsaSigningAlgo(keySize: keySize).verifyBytes(message,
          signature: signature, publicKey: keyPair.publicKey);
    });
  }
}
