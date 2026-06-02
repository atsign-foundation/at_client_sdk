import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_pqc/dart_pqc.dart';

const int _iterations = 200;

Future<void> main() async {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if (lib == null) {
    print('libcrypto not found — FFI columns will be empty.');
    print('');
  }

  await _benchMlKem768(lib);
  await _benchX25519(lib);
  await _benchEd25519(lib);
}

// ── ML-KEM-768 ────────────────────────────────────────────────────────────────

Future<void> _benchMlKem768(DynamicLibrary? lib) async {
  print('=== ML-KEM-768 (${_iterations}x) ===');

  final (int keygenPure, int encapsPure) =
      await _timeMlKem768(MlKem768PureDart.instance);

  if (lib != null) {
    final MlKem768Ffi ffi = MlKem768Ffi.fromLib(lib);
    final (int keygenFfi, int encapsFfi) = await _timeMlKem768(ffi);

    _printComparison('keygen', keygenPure, keygenFfi);
    _printComparison('encaps+decaps', encapsPure, encapsFfi);
  } else {
    _printSingle('keygen', keygenPure);
    _printSingle('encaps+decaps', encapsPure);
  }

  print('');
}

Future<(int keygen, int encaps)> _timeMlKem768(MlKem768Algorithm kem) async {
  // Warmup
  for (int i = 0; i < 5; i++) {
    final PqcKeyPair kp = await kem.generateKeyPair();
    final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
    await kem.decapsulate(kp.secretKey, enc.ciphertext);
    if (kem is MlKem768Ffi) kem.releaseKeyPair(kp);
  }

  final Stopwatch swKeygen = Stopwatch()..start();
  for (int i = 0; i < _iterations; i++) {
    final PqcKeyPair kp = await kem.generateKeyPair();
    if (kem is MlKem768Ffi) kem.releaseKeyPair(kp);
  }
  swKeygen.stop();

  final PqcKeyPair kp = await kem.generateKeyPair();
  final Stopwatch swEncaps = Stopwatch()..start();
  for (int i = 0; i < _iterations; i++) {
    final EncapsulationResult enc = await kem.encapsulate(kp.publicKey);
    await kem.decapsulate(kp.secretKey, enc.ciphertext);
  }
  swEncaps.stop();
  if (kem is MlKem768Ffi) kem.releaseKeyPair(kp);

  return (swKeygen.elapsedMicroseconds, swEncaps.elapsedMicroseconds);
}

// ── X25519 ───────────────────────────────────────────────────────────────────

Future<void> _benchX25519(DynamicLibrary? lib) async {
  print('=== X25519 (${_iterations}x) ===');

  final (int keygenPure, int dhPure) =
      await _timeX25519(X25519PureDart.instance);

  if (lib != null) {
    final (int keygenFfi, int dhFfi) =
        await _timeX25519(X25519Ffi.fromLib(lib));

    _printComparison('keygen', keygenPure, keygenFfi);
    _printComparison('dh (2x per iter)', dhPure, dhFfi);
  } else {
    _printSingle('keygen', keygenPure);
    _printSingle('dh (2x per iter)', dhPure);
  }

  print('');
}

Future<(int keygen, int dh)> _timeX25519(X25519Algorithm x25519) async {
  // Warmup
  for (int i = 0; i < 5; i++) {
    final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
        await x25519.generateKeyPair();
    await x25519.dh(sk, pk);
  }

  final Stopwatch swKeygen = Stopwatch()..start();
  for (int i = 0; i < _iterations; i++) {
    await x25519.generateKeyPair();
  }
  swKeygen.stop();

  final (publicKey: Uint8List alicePk, privateKey: Uint8List aliceSk) =
      await x25519.generateKeyPair();
  final (publicKey: Uint8List bobPk, privateKey: Uint8List bobSk) =
      await x25519.generateKeyPair();
  final Stopwatch swDh = Stopwatch()..start();
  for (int i = 0; i < _iterations; i++) {
    await x25519.dh(aliceSk, bobPk);
    await x25519.dh(bobSk, alicePk);
  }
  swDh.stop();

  return (swKeygen.elapsedMicroseconds, swDh.elapsedMicroseconds);
}

// ── Ed25519 ──────────────────────────────────────────────────────────────────

Future<void> _benchEd25519(DynamicLibrary? lib) async {
  print('=== Ed25519 (${_iterations}x) ===');

  final (int keygenPure, int signPure) =
      await _timeEd25519(Ed25519PureDart.instance);

  if (lib != null) {
    final (int keygenFfi, int signFfi) =
        await _timeEd25519(Ed25519Ffi.fromLib(lib));

    _printComparison('keygen', keygenPure, keygenFfi);
    _printComparison('sign+verify', signPure, signFfi);
  } else {
    _printSingle('keygen', keygenPure);
    _printSingle('sign+verify', signPure);
  }

  print('');
}

Future<(int keygen, int sign)> _timeEd25519(Ed25519Algorithm ed25519) async {
  final Uint8List message = Uint8List.fromList('hello dart_pqc'.codeUnits);

  // Warmup
  for (int i = 0; i < 5; i++) {
    final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
        await ed25519.generateKeyPair();
    final Uint8List sig = await ed25519.sign(sk, message);
    await ed25519.verify(pk, message, sig);
  }

  final Stopwatch swKeygen = Stopwatch()..start();
  for (int i = 0; i < _iterations; i++) {
    await ed25519.generateKeyPair();
  }
  swKeygen.stop();

  final (publicKey: Uint8List pk, privateKey: Uint8List sk) =
      await ed25519.generateKeyPair();
  final Stopwatch swSign = Stopwatch()..start();
  for (int i = 0; i < _iterations; i++) {
    final Uint8List sig = await ed25519.sign(sk, message);
    await ed25519.verify(pk, message, sig);
  }
  swSign.stop();

  return (swKeygen.elapsedMicroseconds, swSign.elapsedMicroseconds);
}

// ── Formatting ────────────────────────────────────────────────────────────────

void _printComparison(String op, int pureUs, int ffiUs) {
  final double pureMsPerOp = pureUs / _iterations / 1000;
  final double ffiMsPerOp = ffiUs / _iterations / 1000;
  final double speedup = pureUs / ffiUs;
  print('  $op');
  print('    pure Dart:   ${pureMsPerOp.toStringAsFixed(3)} ms/op');
  print('    OpenSSL FFI: ${ffiMsPerOp.toStringAsFixed(3)} ms/op'
      '  (${speedup.toStringAsFixed(1)}x faster than pure Dart)');
}

void _printSingle(String op, int pureUs) {
  final double pureMsPerOp = pureUs / _iterations / 1000;
  print('  $op');
  print('    pure Dart: ${pureMsPerOp.toStringAsFixed(3)} ms/op');
}
