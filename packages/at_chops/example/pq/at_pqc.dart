import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';

/// [AtPqc] is the recommended entry point for PQ crypto — it auto-resolves
/// the FFI backend when libcrypto supports it, falling back to pure-Dart
/// otherwise, so callers don't need to pick a backend by hand.
Future<void> main() async {
  await _xWingRoundTrip();
  await _mlDsa65RoundTrip();
}

Future<void> _xWingRoundTrip() async {
  // Generate a fresh key pair for Alice, straight off the resolved backend.
  final kp = await AtPqc.xWing.generateKeyPair();

  // Bob encapsulates using Alice's public key.
  final enc = await AtPqc.xWing.encapsulate(kp.publicKey);

  // Alice decapsulates using her secret key and Bob's ciphertext.
  final Uint8List aliceSharedSecret =
      await AtPqc.xWing.decapsulate(kp.secretKey, enc.ciphertext);

  final String aliceSsString = base64Encode(aliceSharedSecret);
  final String bobSsString = base64Encode(enc.sharedSecret);

  print('X-Wing shared secret match: ${aliceSsString == bobSsString}');
}

Future<void> _mlDsa65RoundTrip() async {
  final kp = await AtPqc.mlDsa65.generateKeyPair();

  final Uint8List message = Uint8List.fromList(utf8.encode('hello pqc'));
  final Uint8List signature =
      await AtPqc.mlDsa65.signBytes(message, secretKey: kp.secretKey);
  // verifyBytes returns normally iff the signature is good — a bad one throws
  // AtSigningVerificationException rather than returning false.
  await AtPqc.mlDsa65
      .verifyBytes(message, signature: signature, publicKey: kp.publicKey);

  print('ML-DSA-65 signature verified');
}
