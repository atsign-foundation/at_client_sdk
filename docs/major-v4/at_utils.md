# `at_utils` 4.0.0

First package in the v4 publish chain (`at_utils` → `at_lookup` → `at_client`) — no
upstream v4 dependency, nothing to stack this branch onto yet.

## Context

`at_utils` is step 3 of the publish ladder
([`implementation-plan.md`](../projects/wasm/implementation-plan.md) §10) and the first of the
three majors this window actually builds — `at_chops` (minor) and `at_auth` (4.0.0-rc1,
[#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179)) already shipped.
It is also the **only one of the three that can close a `wasm_gates.yaml` stanza this
window**: `at_lookup` and `at_client` both carry residual `dart:io` reachability that
survives their cut of this work (see their docs' Exit sections).

`.github/wasm_gates.yaml` today counts `at_utils` and `chalkdart` as `at_chops`'s two
inherited blocked packages — `max_blocked_packages: 2 # at_utils + chalkdart, via the
logger`. Splitting the barrel is what removes both.

## Scope

**In**, at `124982684` (all line numbers checked at this commit):

- **I1 — Split the `at_utils.dart` barrel.** It exports
  `src/networking/pseudo_server_socket.dart` and `src/config/app_config.dart` at
  `at_utils.dart:4-5`. `PseudoServerSocket` is used by `at_server` for ALPN
  multiplexing — **split, do not delete**; both move to `at_utils_io.dart`.
- **I2 — Split `src/logging/handlers.dart`.** `dart:io` (`:1`) and `chalkdart` (`:3`)
  are imported once at the top of the file for four classes: `ConsoleLoggingHandler`
  (`:17`, wraps `print`, stays neutral), `FileLoggingHandler` (`:34`),
  `StdErrLoggingHandler` (`:53`), `CLILoggingHandler` (`:71`). The last three move to
  `at_utils_io.dart`; only `ConsoleLoggingHandler` stays in the default barrel.
- **I3 — `src/config/app_config.dart`** (`dart:io` at `:1`) into the io barrel, or
  inject the config instead of reading it from the file directly.
- **I4 — Publish `at_utils` 4.0.0.**

**Also in scope — chalkdart, or I2 doesn't close the gate.** `chalkdart` (pinned
`">=2.0.9<4.0.0"` in this package's `pubspec.yaml:18`, and in the root workspace
`pubspec.yaml`, `at_cli_commons`, and `at_onboarding_cli`) unconditionally imports
`dart:io` through its own `src/chalk.dart`. `handlers.dart:3` and `at_progress.dart`
(which re-exports `src/logging/progress.dart`) both pull it in — so `at_progress.dart`
is non-neutral today even though it holds no first-party `dart:io`, and `handlers.dart`
is doubly native. I2 is not just a file split; the chalkdart import has to move with it
or the split buys nothing.

**One `@Deprecated` removal:** `AtUtils.formatAtSign`
(`src/atsign_util.dart:77`, `@Deprecated('Use fixAtSign()')`) has exactly one caller
repo-wide — `at_utils/test/fix_at_sign_test.dart:129` — and it is in this package's own
test. Remove it while I2 is open.

**Out of scope:** everything past I4. `at_utils` has no further `I`-phase tasks on the
ladder.

## Blast radius

`at_logger.dart` (the file the split does *not* touch) has **124** import sites
repo-wide; `at_utils.dart` (the barrel being split) has **37**. That asymmetry is why I2
is scoped as a file split rather than a deprecation: almost all of `at_utils`'s reach
runs through the logger, not the barrel.

Five packages reach `AtSignLogger` **only** through `at_utils.dart`'s re-export — they
import neither `at_logger.dart` directly — and break the moment the barrel split lands
without a compensating export: `at_auth`, `at_cli_commons`, `at_client`, `at_contact`,
`at_onboarding_cli`. Each needs `import 'package:at_utils/at_logger.dart';` added (or an
explicit `at_utils_io.dart` import, if it also uses `FileLoggingHandler` /
`StdErrLoggingHandler` / `CLILoggingHandler` — audit call sites before assuming
`at_logger.dart` alone is enough).

Separately, `at_utils: ^4.0.0` needs bumping in ~11 workspace pubspecs once published:
`at_chops`, `at_auth`, `at_cli_commons`, `at_client_flutter`, `at_contact`, `at_policy`,
`at_lookup`, `at_client`, `at_onboarding_cli`, both `tests/*` packages. `resolution:
workspace` means this is not urgent for local dev (path resolution wins), but it is
required before any of those packages can publish against a real `at_utils` release.

## Exit

- `.github/wasm_gates.yaml` gets an `at_utils` stanza: `allowed_offenders: []`, native
  code confined to `at_utils_io.dart`.
- `at_chops`'s `max_blocked_packages` drops from 2 to 0 in the same commit — chalkdart
  moving with I2 clears both inherited offenders at once.
- `grep -rn "^import 'dart:io'" packages/at_utils/lib/at_utils.dart
  packages/at_utils/lib/src/logging/handlers.dart
  packages/at_utils/lib/src/config/app_config.dart` → nothing.
- `dart analyze` clean; `at_utils` test suite green including a new test asserting
  `at_utils.dart` compiles under `dart2wasm` (or the CI job `wasm_gates.yaml` already
  runs for gated packages, once wired for this one).

## Open items

- Owner: whoever lands I2 confirms the five-package re-export fix lands in the *same*
  commit as the split — a staged split breaks `at_auth`/`at_client`/etc. on trunk
  between the two commits.
- No open question on chalkdart's own fix — it is upstream's package, not ours; getting
  it "off the neutral path" here means changing which of *our* files import it, not
  patching chalkdart itself.

## Changelog

```
## 4.0.0-rc1
- BREAKING: `at_utils.dart` no longer exports `PseudoServerSocket` or
  `ApplicationConfiguration` (`app_config.dart`) — import them from the new
  `at_utils_io.dart` barrel.
- BREAKING: `FileLoggingHandler`, `StdErrLoggingHandler`, and `CLILoggingHandler` moved
  to `at_utils_io.dart`; `ConsoleLoggingHandler` is unchanged and stays in `at_utils.dart`.
- Removed: `AtUtils.formatAtSign` (deprecated since 3.x) — use `AtUtils.fixAtSign`.
```
