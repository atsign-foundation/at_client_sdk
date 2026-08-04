// Compile-only smoke test that the web-safe barrel
// `package:at_chops/at_chops.dart` builds under dart2wasm.
//
// Run in CI via `dart compile wasm tool/wasm_compat_check.dart`. It must import
// ONLY at_chops.dart — never at_chops_ffi.dart, which carries dart:ffi/dart:io
// and is not WASM-compatible by design.
//
// The symbols below are touched so tree-shaking does not eliminate the reachable
// graph, exercising the transitive crypto dependencies that matter for WASM:
// better_cryptography (Ed25519), cryptography + pointycastle (X-Wing), pqcrypto
// (ML-DSA), and encrypt (IV generation).
import 'package:at_chops/at_chops.dart';

void main() {
  final symbols = <Object>[
    Ed25519SigningAlgo(),
    XWingPureDartAlgo.instance,
    MlDsa65PureDartAlgo(),
    Md5HashingAlgo(),
    SHA256HashingAlgo(),
    InitialisationVector.random(12),
  ];
  print('at_chops WASM smoke test reached ${symbols.length} symbols');
}
