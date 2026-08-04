import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';

Future<void> main() async {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if (lib == null) {
    print('libcrypto not found');
    return;
  }
  final MlDsa65FfiAlgo algo = MlDsa65FfiAlgo.fromLib(lib);

  // Alice generates a key pair. Unlike ML-KEM-768, ML-DSA-65 secret keys are
  // real serializable bytes — both keys can be persisted and round-tripped.
  final ({Uint8List publicKey, Uint8List secretKey}) kp =
      await algo.generateKeyPair();

  print(
      'Public key (${kp.publicKey.length} bytes): ${base64Encode(kp.publicKey)}');
  print(
      'Secret key (${kp.secretKey.length} bytes): ${base64Encode(kp.secretKey)}');

  // Alice signs a message with her secret key.
  final Uint8List message = Uint8List.fromList(utf8.encode('hello pqc'));
  final Uint8List signature =
      await algo.signBytes(message, secretKey: kp.secretKey);

  print('Signature (${signature.length} bytes): ${base64Encode(signature)}');

  // Bob verifies the signature against Alice's public key.
  final bool ok = await algo.verifyBytes(message,
      signature: signature, publicKey: kp.publicKey);

  print('Verified: $ok');
}
