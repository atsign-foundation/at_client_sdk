// Compile-only smoke test that the web-safe barrel
// `package:at_chops/at_chops.dart` builds under dart2wasm.
//
// Run in CI via `dart compile wasm tool/wasm_compat_check.dart`. It must import
// ONLY at_chops.dart — never at_chops_ffi.dart, which carries dart:ffi/dart:io
// and is not WASM-compatible by design.
//
// The symbols below are touched so tree-shaking does not eliminate the reachable
// graph, exercising the transitive crypto dependencies that matter for WASM:
// pointycastle (AES, RSA + ASN.1, ECDSA, Argon2id, digests, Fortuna), cryptography
// (Ed25519, X25519) and pqcrypto (ML-DSA, ML-KEM). Argon2id is here specifically
// because pointycastle picks its implementation by conditional import — the
// Register64 one off dart:io — so only a real WASM build proves that path
// compiles.
import 'package:at_chops/at_chops.dart';

void main() {
  final symbols = <Object>[
    AesCtrEncryptionAlgo(32),
    AesGcm256EncryptionAlgo(),
    RsaEncryptionAlgo(),
    RsaSigningAlgo(),
    EccSigningAlgo(),
    Ed25519SigningAlgo(),
    XWingPureDartAlgo.instance,
    MlDsa65PureDartAlgo(),
    Argon2idHashingAlgo(),
    Md5HashingAlgo(),
    SHA256HashingAlgo(),
    InitialisationVector.random(12),
  ];
  print('at_chops WASM smoke test reached ${symbols.length} symbols');
}
