import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

Future<void> main() async {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if(lib == null) {
    print('lib is null');
    return;
  }
  X25519FfiAlgo x25519FfiAlgo = X25519FfiAlgo.fromLib(lib);

  final AtX25519KeyPair atX25519KeyPair1 = await AtChopsUtil.generateX25519KeyPair();
  final AtPrivateKey x25519PrivateKey1 = atX25519KeyPair1.atPrivateKey;
  final AtPublicKey x25519PublicKey1 = atX25519KeyPair1.atPublicKey;
  final Uint8List x25519PrivateKeyBytes1 = base64Decode(x25519PrivateKey1.privateKey);
  final Uint8List x25519PublicKeyBytes1 = base64Decode(x25519PublicKey1.publicKey);

  final AtX25519KeyPair atX25519KeyPair2 = await AtChopsUtil.generateX25519KeyPair();
  final AtPrivateKey x25519PrivateKey2 = atX25519KeyPair2.atPrivateKey;
  final AtPublicKey x25519PublicKey2 = atX25519KeyPair2.atPublicKey;
  final Uint8List x25519PrivateKeyBytes2 = base64Decode(x25519PrivateKey2.privateKey);
  final Uint8List x25519PublicKeyBytes2 = base64Decode(x25519PublicKey2.publicKey);

  final Uint8List aliceSharedSecret = await x25519FfiAlgo.dh(x25519PrivateKeyBytes1, x25519PublicKeyBytes2);
  final Uint8List bobSharedSecret = await x25519FfiAlgo.dh(x25519PrivateKeyBytes2, x25519PublicKeyBytes1);

  final String aliceSsString = base64Encode(aliceSharedSecret);
  final String bobSsString = base64Encode(bobSharedSecret);

  print('Alice ss (${aliceSsString.length}): ${aliceSsString} | bytes (${aliceSharedSecret.length})');
  print('Bob ss (${bobSsString.length}): ${bobSsString} | bytes (${bobSharedSecret.length})');
}
