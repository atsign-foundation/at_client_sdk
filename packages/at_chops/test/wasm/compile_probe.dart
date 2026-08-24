// Compiled by CI, never run. `dart compile wasm` rejects dart:ffi, dart:html,
// dart:js and dart:mirrors outright, so a barrel that reaches one fails here. It
// ACCEPTS dart:io and ships a throwing stub — that is what dep_tree_test.dart is
// for. Not named *_test.dart, so `dart test` ignores it.
//
// at_chops_ffi.dart is deliberately absent: it is the FFI island, it does not
// compile to wasm, and that failing is the point. dep_tree_test.dart asserts it
// still carries the algorithms it quarantines.
//
// The imports below are the entire point of this file — merely reaching them
// is what exercises the wasm compile — so they are intentionally unused.
// ignore_for_file: unused_import
import 'package:at_chops/at_chops.dart';
import 'package:at_chops/types.dart';

void main() {}
