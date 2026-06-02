import 'dart:typed_data';

import 'package:dart_pqc/dart_pqc.dart';

Future<void> main() async {
  await _demo('ML-KEM-768', MlKem768PureDart.instance);
  await _demo('X25519', X25519PureDart.instance);
}

Future<void> _demo(String label, KemAlgorithm kem) async {
  print('=== $label ===');

  // Key generation
  final PqcKeyPair kp = await kem.generateKeyPair();
  print('pk: ${kp.publicKey.length} bytes');
  print('sk: ${kp.secretKey.length} bytes');

  // Encapsulation (sender side)
  final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
  print('ct: ${enc.ciphertext.length} bytes');
  print('ss (sender): ${_hex(enc.sharedSecret)}');

  // Decapsulation (receiver side)
  final Uint8List ss2 = await kem.decapsulate(kp.secretKey, enc.ciphertext);
  print('ss (recvr): ${_hex(ss2)}');
  print('match: ${_eq(enc.sharedSecret, ss2)}');
  print('');
}

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
