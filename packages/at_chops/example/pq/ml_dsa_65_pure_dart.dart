import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

Future<void> main() async {
  // Alice generates a key pair. Both public and secret keys are raw bytes.
  final ({Uint8List publicKey, Uint8List secretKey}) kp =
      await MlDsa65PureDartAlgo.generateKeyPair();

  print('Public key (${kp.publicKey.length} bytes): ${base64Encode(kp.publicKey)}');
  print('Secret key (${kp.secretKey.length} bytes): ${base64Encode(kp.secretKey)}');

  // Alice signs a message with her secret key.
  final algo = MlDsa65PureDartAlgo();
  final Uint8List message = Uint8List.fromList(utf8.encode('hello pqc'));
  final Uint8List signature = await algo.signBytes(message, kp.secretKey);

  print('Signature (${signature.length} bytes): ${base64Encode(signature)}');

  // Bob verifies the signature against Alice's public key.
  final bool ok = await algo.verifyBytes(message, signature, kp.publicKey);

  print('Verified: $ok');
}
