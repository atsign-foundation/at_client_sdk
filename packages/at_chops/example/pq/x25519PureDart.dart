import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';

Future<void> main() async {
  final X25519PureDartAlgo algo = X25519PureDartAlgo.instance;

  final ({Uint8List publicKey, Uint8List privateKey}) kp1 =
      await algo.generateKeyPair();
  final ({Uint8List publicKey, Uint8List privateKey}) kp2 =
      await algo.generateKeyPair();

  final Uint8List aliceSharedSecret = await algo.dh(kp1.privateKey, kp2.publicKey);
  final Uint8List bobSharedSecret = await algo.dh(kp2.privateKey, kp1.publicKey);

  final String aliceSsString = base64Encode(aliceSharedSecret);
  final String bobSsString = base64Encode(bobSharedSecret);

  print('Alice ss (${aliceSsString.length}): $aliceSsString | bytes (${aliceSharedSecret.length})');
  print('Bob ss   (${bobSsString.length}): $bobSsString | bytes (${bobSharedSecret.length})');
  print('Match: ${aliceSsString == bobSsString}');
}
