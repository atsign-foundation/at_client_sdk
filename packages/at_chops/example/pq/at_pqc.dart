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
  final XWingKeyPair kp = await XWingKeyPair.generate();

  // Bob encapsulates using Alice's public key.
  final enc = await AtPqc.xWing.encapsulate(kp.publicKeyBytes);

  // Alice decapsulates using her secret key and Bob's ciphertext.
  final Uint8List aliceSharedSecret =
      await AtPqc.xWing.decapsulate(kp.privateKeyBytes, enc.ciphertext);

  final String aliceSsString = base64Encode(aliceSharedSecret);
  final String bobSsString = base64Encode(enc.sharedSecret);

  print('X-Wing shared secret match: ${aliceSsString == bobSsString}');
}

Future<void> _mlDsa65RoundTrip() async {
  final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();

  final Uint8List message = Uint8List.fromList(utf8.encode('hello pqc'));
  final Uint8List signature =
      await AtPqc.mlDsa65.signBytes(message, kp.privateKeyBytes);
  final bool ok =
      await AtPqc.mlDsa65.verifyBytes(message, signature, kp.publicKeyBytes);

  print('ML-DSA-65 signature verified: $ok');
}
