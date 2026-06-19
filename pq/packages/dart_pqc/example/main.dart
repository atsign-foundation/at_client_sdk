import 'dart:typed_data';

import 'package:dart_pqc/dart_pqc.dart';

Future<void> main() async {
  await _mlKem768Demo();
  await _x25519Demo();
  await _ed25519Demo();
}

Future<void> _mlKem768Demo() async {
  print('=== ML-KEM-768 ===');
  final MlKem768Algorithm kem = resolveMlKem768();
  print('implementation: ${kem.runtimeType}');

  final PqcKeyPair kp = await kem.generateKeyPair();
  print('pk: ${kp.publicKey.length} bytes');
  print('sk: ${kp.secretKey.length} bytes');

  final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
  print('ct: ${enc.ciphertext.length} bytes');
  print('ss (sender):    ${_hex(enc.sharedSecret)}');

  final Uint8List ss = await kem.decapsulate(kp.secretKey, enc.ciphertext);
  print('ss (recipient): ${_hex(ss)}');
  print('match: ${_eq(enc.sharedSecret, ss)}');
  print('');
}

Future<void> _x25519Demo() async {
  print('=== X25519 ===');
  final X25519Algorithm x25519 = resolveX25519();
  print('implementation: ${x25519.runtimeType}');

  final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
      await x25519.generateKeyPair();
  final (publicKey: Uint8List bobPk, privateKey: Uint8List bobSk) =
      await x25519.generateKeyPair();

  print('Alice pk: ${alicePk.length} bytes');
  print('Bob   pk: ${bobPk.length} bytes');

  final Uint8List ss1 = await x25519.dh(aliceSk, bobPk);
  final Uint8List ss2 = await x25519.dh(bobSk, alicePk);

  print('ss (Alice): ${_hex(ss1)}');
  print('ss (Bob):   ${_hex(ss2)}');
  print('match: ${_eq(ss1, ss2)}');
  print('');
}

Future<void> _ed25519Demo() async {
  print('=== Ed25519 ===');
  final Ed25519Algorithm ed25519 = resolveEd25519();
  print('implementation: ${ed25519.runtimeType}');

  final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
      await ed25519.generateKeyPair();
  print('pk: ${pk.length} bytes');
  print('sk: ${sk.length} bytes');

  final Uint8List message = Uint8List.fromList('hello dart_pqc'.codeUnits);
  final Uint8List signature = await ed25519.sign(sk, message);
  print('signature: ${signature.length} bytes');

  final bool valid = await ed25519.verify(pk, message, signature);
  print('valid: $valid');
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
