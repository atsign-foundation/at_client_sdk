// Compile target for CI's wasm check. Imports `at_auth.dart` — never
// `at_auth_io.dart` — so the wasm-safe surface has to build:
//
//   dart compile wasm tool/wasm_entry.dart -o /tmp/at_auth.wasm
//
// What that catches: `dart:ffi` or `dart:mirrors` anywhere in the transitive
// graph, which are hard errors under dart2wasm. What it does not: `dart:io`,
// which dart2wasm compiles to a stub that throws only when called.
import 'package:at_auth/at_auth.dart';

void main() {
  // Name the entry points so the graph is genuinely reachable rather than
  // tree-shaken away.
  print([
    AtAuth.create,
    AtEnrollment.create,
    AtKeys.generate,
    EphemeralAtKeysIo.new,
    RegistrarService.new,
  ].length);
}
