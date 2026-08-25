# wasm_shakedown

Dev-only tooling that keeps the packages in `.github/wasm_gates.yaml` compiling to
wasm and stops them gaining browser-hostile imports. Not published; run by
`dart run wasm_shakedown` and by the `wasm_shakedown` and `wasm_ratchet` jobs in
`.github/workflows/at_libraries.yaml`.

```bash
dart run wasm_shakedown                    # every gated package
dart run wasm_shakedown --package at_auth  # just one (repeatable)
dart run wasm_shakedown --config PATH      # a config other than the default
```

The default config is `.github/wasm_gates.yaml`, resolved against the pub workspace
root so the command works from anywhere in the repo. CI passes `--config` explicitly,
so the workflow names the file rather than leaning on that default.

at_chops and at_auth are gated today — both already web-safe, at_chops behind
`at_chops_ffi.dart` and at_auth behind `at_auth_io.dart`, so each gate holds a line
rather than recording a backlog. at_utils, at_lookup and at_client own 3, 6 and 7
offenders respectively and join as each is ported.

## Why this exists

`dart compile wasm` **does not reject `dart:io`.** It ships a stub whose members
throw `Unsupported operation` when called, so a browser-hostile import compiles
clean and fails in the browser instead. Measured on Dart 3.12:

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

## Adding a package

**One stanza in `.github/wasm_gates.yaml`** — nothing in the package, nothing in CI.
Run it, read the reported figures off the failure, and set the baselines from them.

```yaml
at_utils:
  ratchets:
    - barrel: package:at_utils/at_utils.dart
      allowed_offenders: []
      max_blocked_packages: 2
      min_files_walked: 150
  probe:
    - package:at_utils/at_utils.dart
  controls:
    - barrel: package:at_utils/at_utils_io.dart
      reaches_library: dart:io
      because: the filesystem code it exists to quarantine
```

## The three keys

| Key        | Catches                                                             |
| ---------- | ------------------------------------------------------------------- |
| `ratchets` | `dart:io`, and anything else forbidden, reachable from a barrel      |
| `probe`    | the libraries dart2wasm rejects outright                             |
| `controls` | the ratchet above having quietly stopped proving anything            |

`ratchets` and `probe` do not cover each other: the walk sees what the compiler waves
through, the compile sees hard rejections.

`controls` are the one that's easy to skip. Every ratchet check is about what the walk
did *not* find, and a walk that found nothing satisfies all of them — so a control
walks the other side of the platform seam and asserts the walk still *reaches*
something known to be there. Without one, `at_chops_ffi.dart` could be emptied and the
gate would still read green. Two axes, each weak alone: `reaches_library` pins that a
forbidden library is still reached but not where, `reaches_file` pins a source but not
what it imports. Controls resolve with io semantics; `environment: web` pins the other
branch of a conditional export.

The walk crosses package boundaries via `.dart_tool/package_config.json` and resolves
configurable URIs the way the target platform would. Run `dart pub get` first.

The probe is generated from `probe:` into `.dart_tool/wasm_shakedown/` and deleted on
success, or kept so the failing command can be re-run. It must live under the repo
root: `dart compile wasm` has no `--packages` flag and walks up from the entry file, so
a probe in `Directory.systemTemp` resolves nothing.

## Baselines

Each ratchet names the sources allowed to reach a forbidden library, plus a ceiling on
how many packages anywhere in the graph own one. Both are **one-way**:

- A source outside `allowed_offenders`, or a count above the ceiling, fails.
- Fixing a source, or dropping a dependency, **passes with no edit here.** The
  baseline just goes loose, and the figures say so — `6/7 offenders` means one listed
  file no longer reaches anything.

So the only edit ever required is tightening, whenever it is convenient rather than in
the same commit as the fix. To widen one, add the path; the failure prints the full
live walk. There is deliberately no way to write a baseline back from a run — a
generator existed once and was removed, because the failure output already carries
what it would have printed.

Both gated packages have an empty allow list. at_chops' ceiling of 2 is `at_utils` and
`chalkdart` via the logger; at_auth's 4 adds `at_lookup` and `at_server_status`.

Every run prints its figures whether or not it fails:

```
package:at_chops/at_chops.dart — 582 files walked, 0/0 offenders, 2/2 blocked
```

`min_files_walked` guards the rest — every other check is about what the walk did
*not* find, and a stalled walk finds nothing either, so set it near the real figure.
Controls need no such floor: their checks are positive.

## Layout

| File                      | Role                                                   |
| ------------------------- | ------------------------------------------------------ |
| `wasm_shakedown.dart`     | the graph walk and the platform environments           |
| `config.dart`             | parses the gate config, strictly                       |
| `verdict.dart`            | what a walk *means*. Pure — no processes, no filesystem |
| `runner.dart`             | runs one stanza. Decides nothing, prints nothing        |
| `bin/wasm_shakedown.dart` | the CLI. The only file that prints                     |

The split is what makes the gates testable: `verdict.dart` judges a walk it is handed,
so `test/verdict_test.dart` writes down the walks it wants instead of arranging a
filesystem that produces them. That is the only way to cover the baseline logic —
both gated packages baseline an empty allow list over a package owning no offender, so
the live figures cannot tell a correct subtraction from a reversed one.

```bash
cd tools/wasm_shakedown && dart test   # the tooling's own tests
dart run wasm_shakedown                # the gates, from anywhere in the repo
```

Every suite here reads the filesystem, so all of them are `@TestOn('vm')`.

## What these gates do not prove

That the code is correct under WasmGC. A package can compile clean and still mishandle
a 64-bit integer, a string encoding, or an async ordering difference. Absence from the
graph is a strong guarantee, but only about *reachability*; and the probe's
`void main() {}` tree-shakes hard, so it proves the front end accepts the import graph,
not that anything codegens.

Executing the suites under Node would cover the rest, for the paths the tests touch.
That step is **not in CI**, and its absence is honest rather than an oversight: on the
hosted runner every suite fails to load before any test body runs, because the CJS
bootstrap calls `instantiate` from the ESM `.mjs` init file and gets `undefined`. It
works on Dart 3.12 + Node 24 locally, so it is a toolchain-version problem rather than
a finding about our code. It comes back once Dart and Node are pinned to a pair where
a failure means something.
