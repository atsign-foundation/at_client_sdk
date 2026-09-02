import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

Future<void> main() async {
  final MlKem768PureDartAlgo algo = MlKem768PureDartAlgo.instance;

  // Alice generates a key pair. Both public and secret keys are raw bytes and
  // are serializable (unlike the FFI backend's opaque handles).
  final ({Uint8List publicKey, Uint8List secretKey}) kp =
      await algo.generateKeyPair();

  print(
      'Public key (${kp.publicKey.length} bytes): ${base64Encode(kp.publicKey)}');
  print(
      'Secret key (${kp.secretKey.length} bytes): ${base64Encode(kp.secretKey)}');

  // Bob encapsulates using Alice's public key.
  final ({Uint8List ciphertext, Uint8List sharedSecret}) bobResult =
      await algo.encapsulate(kp.publicKey);

  // Alice decapsulates using her secret key and Bob's ciphertext.
  final Uint8List aliceSharedSecret =
      await algo.decapsulate(kp.secretKey, bobResult.ciphertext);

  final String aliceSsString = base64Encode(aliceSharedSecret);
  final String bobSsString = base64Encode(bobResult.sharedSecret);

  print('Alice ss (${aliceSharedSecret.length} bytes): $aliceSsString');
  print('Bob ss   (${bobResult.sharedSecret.length} bytes): $bobSsString');
  print('Match: ${aliceSsString == bobSsString}');
}
