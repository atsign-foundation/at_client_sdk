# wasm_shakedown

Dev-only tooling that keeps the platform-neutral packages neutral. Not published;
a workspace member used by tests and by CI's `wasm_shakedown_tests` and
`wasm_ratchet` jobs in `.github/workflows/at_libraries.yaml`.

## Why this exists

`dart compile wasm` **does not reject `dart:io`.** It ships a stub whose members
throw `Unsupported operation` when called, so a browser-hostile import compiles
clean and fails in the browser instead. `dart compile js` behaves the same way and
accepts `dart:html` and `dart:js` on top. Measured on Dart 3.12:

| Library        | dart2wasm | dart2js  |
| -------------- | --------- | -------- |
| `dart:io`      | compiles  | compiles |
| `dart:isolate` | compiles  | compiles |
| `dart:html`    | rejected  | compiles |
| `dart:js`      | rejected  | compiles |
| `dart:ffi`     | rejected  | rejected |
| `dart:mirrors` | rejected  | rejected |

No Dart web compiler gates `dart:io`. A build step therefore cannot police
neutrality, and that is the whole reason this package is a graph walk rather than
a compile.

## The gate

| Gate                 | Lives in                                      | Catches                                    |
| -------------------- | --------------------------------------------- | ------------------------------------------ |
| Dependency-tree walk | each package's `test/wasm/dep_tree_test.dart` | a platform library reachable from a barrel |

The walk crosses package boundaries via `.dart_tool/package_config.json`, so it
covers siblings and third-party packages, and it resolves configurable URIs the
way the *target* platform would — `dart.library.io` false, `dart.library.js_interop`
true for a web build. Run `dart pub get` first or it has nothing to resolve
against.

## Regenerating a baseline

Each `dep_tree_test.dart` pins the exact set of platform libraries reachable from
its barrels. It is a **two-way** ratchet: a new entry means someone introduced a
browser-hostile import, a missing entry means a blocker was fixed and the baseline
owes an update. Both directions fail the build, and both are meant to — the point
is that either way somebody reads the change.

Do not hand-edit a baseline. Regenerate it:

```bash
dart run wasm_shakedown:baseline package:at_lookup/at_lookup.dart
```

and paste the two literals it prints. Pass `--io` to walk with native semantics
instead — that is how you assert the *inverse* half of a seam, e.g. that
`at_chops_ffi.dart` still carries the FFI algorithms it exists to quarantine.
Without that half, "the web barrel is clean" goes vacuously green the day the two
barrels get merged.

## Running it

```bash
cd tools/wasm_shakedown && dart test    # the walk's own tests
cd packages/at_lookup   && dart test test/wasm/dep_tree_test.dart
```

Every suite here reads the filesystem, so all of them are `@TestOn('vm')`. They
are deliberately invisible to the `dart test -p node -c dart2wasm` platform run,
which exists to execute the *libraries* under WasmGC.

## What this gate does not prove

That the code is correct under WasmGC. A package can be perfectly neutral and
still mishandle a 64-bit integer, a string encoding, or an async ordering
difference. Absence from the graph is a strong guarantee precisely because it does
not depend on a test exercising the path — but it is a guarantee about reachability
only. Executing the suites under Node is what covers the rest, and it covers only
the paths the tests touch. Report both, never one alone.
