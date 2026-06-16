import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

Future<void> main() async {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if (lib == null) {
    print('libcrypto not found');
    return;
  }
  final MlKem768FfiAlgo algo = MlKem768FfiAlgo.fromLib(lib);

  // Alice generates a key pair. The secretKey is an opaque 8-byte handle —
  // valid only within this process via this algo instance.
  final ({Uint8List publicKey, Uint8List secretKey}) kp =
      await algo.generateKeyPair();

  print('Public key (${kp.publicKey.length} bytes): ${base64Encode(kp.publicKey)}');

  // Bob encapsulates using Alice's public key — produces a ciphertext and
  // his copy of the shared secret.
  final ({Uint8List ciphertext, Uint8List sharedSecret}) bobResult =
      await algo.encapsulate(kp.publicKey);

  // Alice decapsulates using her opaque secret-key handle and Bob's ciphertext.
  final Uint8List aliceSharedSecret =
      await algo.decapsulate(kp.secretKey, bobResult.ciphertext);

  final String aliceSsString = base64Encode(aliceSharedSecret);
  final String bobSsString = base64Encode(bobResult.sharedSecret);

  print('Alice ss (${aliceSharedSecret.length} bytes): $aliceSsString');
  print('Bob ss   (${bobResult.sharedSecret.length} bytes): $bobSsString');
  print('Match: ${aliceSsString == bobSsString}');

  algo.releaseKeyPair(kp);
}
