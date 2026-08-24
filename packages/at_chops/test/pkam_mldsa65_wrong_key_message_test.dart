import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/spec/ml_dsa_65_spec.dart';
import 'package:at_commons/at_commons.dart' show AtSigningException;
import 'package:test/test.dart';

/// A PKAM key of the wrong length is almost never a corrupt key.
///
/// The way a caller reaches this frame holding an RSA private key while
/// declaring ML-DSA-65 is by naming one enrollment's algorithm and carrying
/// another enrollment's credentials — a retrofitted keyfile holds ML-DSA
/// material for the new enrollment and the original RSA keypair in the flat
/// fields, and the two are selected separately. Reported as a bare byte count
/// it reads as corruption, and the search starts in the wrong place.
void main() {
  PkamMlDsa65SigningAlgo algoWithKeyOfLength(int bytes) =>
      PkamMlDsa65SigningAlgo(AtPkamKeyPair.create(
        base64Encode(Uint8List(MlDsa65Sizes.publicKeyBytes)),
        base64Encode(Uint8List(bytes)),
      ));

  test('an RSA-sized PKAM key names the likely cause, not just the length', () {
    // 1216 bytes: the length an RSA-2048 private key decodes to, and the
    // value this message was written for.
    expect(
      () => algoWithKeyOfLength(1216).sign(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AtSigningException>().having(
          (e) => e.toString(),
          'says the size, the expected size, and the likely cause',
          allOf(
            contains('1216'),
            contains('${MlDsa65Sizes.secretKeyBytes}'),
            contains('RSA-2048'),
            contains('different'),
          ))),
      reason: 'a caller meeting this is looking at a credential/algorithm '
          'mismatch, and the message has to say so - the byte count alone '
          'sends them looking for a corrupt key',
    );
  });

  test('a key that is merely the wrong length says so without guessing', () {
    // The negative control: the RSA hint must be CONDITIONAL, or it is an
    // assertion the message makes about every wrong key regardless of size.
    expect(
      () => algoWithKeyOfLength(7).sign(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AtSigningException>().having(
          (e) => e.toString(),
          'states the mismatch and claims nothing about its cause',
          allOf(
            contains('7 bytes'),
            contains('${MlDsa65Sizes.secretKeyBytes}'),
            isNot(contains('RSA-2048')),
          ))),
      reason: 'a 7-byte key is not an RSA key, and saying it might be would '
          'be a worse message than the byte count this replaced',
    );
  });

  test('a correctly sized key is not refused here', () async {
    // Proves the guard discriminates on length rather than refusing the path:
    // a real ML-DSA-65 keypair must sign.
    final pair = await MlDsa65KeyPair.generate();
    final algo = PkamMlDsa65SigningAlgo(AtPkamKeyPair.create(
        pair.atPublicKey.publicKey, pair.atPrivateKey.privateKey));
    expect(algo.sign(Uint8List.fromList([1, 2, 3])), isNotEmpty,
        reason: 'a valid ML-DSA-65 secret key must sign; a guard that '
            'refused this would have replaced a bad message with a broken '
            'signing path');
  });
}
