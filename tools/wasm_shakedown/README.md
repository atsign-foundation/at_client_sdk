# wasm_shakedown

Dev-only tooling that keeps at_chops compiling to wasm and stops it gaining
browser-hostile imports. Not published; a workspace member used by
`packages/at_chops/test/wasm/` and by CI's `wasm_ratchet` job in
`.github/workflows/at_libraries.yaml`.

Scoped to at_chops on purpose. It is the only core package already web-safe, so it
is the only one where a gate holds a line rather than recording a backlog.
at_utils, at_lookup, at_client and at_auth get the same pair of files as each is
ported — the tooling here is package-agnostic and needs no change to take them.

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

No Dart web compiler gates `dart:io`. That is the whole reason a graph walk exists
here alongside the compile.

## The two gates

| Gate                 | Lives in                                    | Catches                                               |
| -------------------- | ------------------------------------------- | ----------------------------------------------------- |
| Dependency-tree walk | `at_chops/test/wasm/dep_tree_test.dart`     | `dart:io` (and anything else) reachable from a barrel  |
| Compile probe        | `at_chops/test/wasm/compile_probe.dart`     | the libraries dart2wasm rejects outright              |

Neither covers the other, which is why there are two. The walk sees what the
compiler waves through; the compile sees hard rejections and answers "does this
package build for wasm at all".

The walk crosses package boundaries via `.dart_tool/package_config.json`, so it
covers siblings and third-party packages, and it resolves configurable URIs the way
the *target* platform would — `dart.library.io` false, `dart.library.js_interop`
true for a web build. Run `dart pub get` first or it has nothing to resolve against.

The probe is a list of imports and an empty `main()`. It must live inside the
package it probes: `dart compile wasm` has no `--packages` flag and resolves
`package:` URIs by walking up from the entry file. It is not named `*_test.dart`, so
`dart test` ignores it. `at_chops_ffi.dart` is deliberately absent from it — that
barrel does not compile to wasm, and that is the point.

## Baselines

`dep_tree_test.dart` names the package sources allowed to reach a forbidden library,
plus a ceiling on how many packages anywhere in the graph own one. Both are
**one-way**:

- A source outside `allowedOffenders`, or a blocked count above the ceiling, fails.
  That is the regression the gate exists to catch.
- Fixing a source, or dropping a dependency, **passes with no edit here.** The
  baseline just becomes loose, and the printed figures say so — `6/7 offenders`
  means one listed file is no longer reaching anything.

So the only edit ever required is tightening, and that can happen whenever it is
convenient rather than in the same commit as the fix. To widen a baseline
deliberately, add the path; the failure message prints the full live walk, so there
is nothing to transcribe.

at_chops' own set is empty — it owns no offender, and its blocked ceiling of 2 is
`at_utils` and `chalkdart`, inherited through the logger. Those come off when the
at_utils barrel split lands.

Every run prints its figures whether or not it fails:

```
package:at_chops/at_chops.dart — 574 files walked, 0/0 offenders, 2/2 blocked
```

`minFilesWalked` guards the rest. Every other assertion is about what the walk did
*not* find, and a traversal that stalled at the entry point also finds nothing.

## Adding a package

Two files, no tooling change:

1. `packages/<pkg>/test/wasm/dep_tree_test.dart` calling `ratchetGroup` once per
   barrel. Run it, read the reported figures off the failure, and set
   `allowedOffenders` / `maxBlockedPackages` / `minFilesWalked` from them.
2. `packages/<pkg>/test/wasm/compile_probe.dart` importing every web-safe barrel
   plus `void main() {}`.

Then add the two steps to `wasm_ratchet`.

## Running it

```bash
cd tools/wasm_shakedown && dart test              # the walk's own tests
cd packages/at_chops    && dart test test/wasm/dep_tree_test.dart
cd packages/at_chops    && dart compile wasm test/wasm/compile_probe.dart -o /tmp/probe.wasm
```

Every suite here reads the filesystem, so all of them are `@TestOn('vm')`.

## What these gates do not prove

That the code is correct under WasmGC. A package can compile clean and still
mishandle a 64-bit integer, a string encoding, or an async ordering difference. Two
specific limits worth knowing:

- Absence from the graph is a strong guarantee precisely because it does not depend
  on a test exercising the path — but it is a guarantee about *reachability* only.
- The compile probe's `void main() {}` tree-shakes aggressively. It proves the front
  end accepts the whole import graph, which is what catches a hard rejection; it
  does not prove codegen for code nothing calls.

Executing the suites under Node is what would cover the rest, and only for the paths
the tests touch. That step is **not in CI**, and its absence is the honest state of
things rather than an oversight: on the hosted runner every suite fails to load
before any test body runs, because the generated CJS bootstrap calls `instantiate`
from the ESM `.mjs` init file and gets `undefined`. The same command works on
Dart 3.12 + Node 24 locally, so it is a toolchain-version problem, not a finding
about our code. It comes back once Dart and Node are pinned to a pair where a failure
means something.
