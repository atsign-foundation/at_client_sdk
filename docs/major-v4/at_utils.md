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

Separately, `at_utils: ^4.0.0` needed bumping in 22 workspace pubspecs, not the ~11
originally estimated — **done**, in the same commit as the version bump. `resolution:
workspace` means the constraint mismatch isn't latent for local dev the way this section
originally assumed: pub workspaces still validate every declared constraint against the
member's actual version, so the stale `^3.x` ranges failed `dart pub get` immediately,
not just at publish time.

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

- ~~Owner: whoever lands I2 confirms the five-package re-export fix lands in the
  *same* commit as the split~~ — **landed, and narrower than scoped.** Verified against
  actual call sites rather than the estimate: `at_auth` and `at_contact` only reach
  `AtSignLogger`/`AtUtils.fixAtSign` through `at_utils.dart`, both untouched by this
  split, so neither needed a change. The real compensating fix was
  `AtSignLogger.stdErrLoggingHandler` — a static field on the neutral `AtSignLogger`
  class holding a concrete `StdErrLoggingHandler()`, not caught by the original
  blast-radius citation. Left in place, it would have kept `dart:io` reachable from
  `at_utils.dart` through `AtSignLogger` itself, silently defeating I2. Removed the
  field; the three real call sites (`at_cli_commons/cli_base.dart`,
  `at_onboarding_cli/auth_cli.dart`, `tests/at_functional_test`, plus
  `at_client_flutter`'s dockerstats example — none of them the five originally named)
  now construct `StdErrLoggingHandler()` directly against `at_utils_io.dart`.
  `at_client/src/rpc/at_rpc.dart` had the same field wired into `AtRpcClient`'s
  default logger, but `at_rpc.dart` is exported from `at_client.dart`'s own barrel —
  porting the io import there would have piped `dart:io` into at_client's future
  barrel for no reason. Dropped the override instead; `AtRpcClient` now uses
  `AtSignLogger`'s ordinary default (`ConsoleLoggingHandler`), same as everything else
  that doesn't ask for stderr.
- No open question on chalkdart's own fix — it is upstream's package, not ours; getting
  it "off the neutral path" here means changing which of *our* files import it, not
  patching chalkdart itself.
- `at_client_flutter/examples/dockerstats` was the first of **six** standalone
  (non-workspace) example pubspecs that resolve `at_utils` from pub.dev unless
  overridden: also `at_client/example`, `at_client_flutter/example`,
  `at_client_flutter/examples/todos`, `at_chat_flutter/example`, and
  `at_policy/example`. Each already overrode its other local packages (`at_client`,
  `at_onboarding_cli`, etc.) to path but not `at_utils` itself — so once those
  overridden packages started declaring `at_utils: ^4.0.0`, pub.dev had nothing to
  offer and resolution failed. Added the same `at_utils: path: ...` override to all
  six, consistent with their siblings. (The dockerstats file also has a pre-existing,
  unrelated `FileAtKeysIo` undefined-method error, confirmed present before this
  change — not introduced here.)
- **New blocker, not anticipated by this doc:** `at_persistence_secondary_server`
  (external, published from `atsign-foundation/at_server`, not a workspace member) pins
  `at_utils: ^3.0.19` in its own pubspec, and nothing in this repo can edit that. Every
  workspace member that depends on it — `at_client`, `at_onboarding_cli`,
  `at_functional_test`, and the root itself — failed to resolve against local `at_utils`
  4.0.0 until this was addressed. Stopgap: pushed
  `st/at_persistence-at_utils-4.0.0-compat` to `at_server`, widening its
  `at_persistence_secondary_server` constraint to `at_utils: ">=3.0.19 <5.0.0"` (audited:
  nothing in that package touches any symbol the barrel split removed, so it's a
  constraint-only change), and added a `git`-ref `dependency_overrides` entry for
  `at_persistence_secondary_server` in the root `pubspec.yaml` pointing at that branch.
  **This is temporary** — it needs a real `at_persistence_secondary_server` release with
  the widened constraint before this override can come out.

## Changelog

```
## 4.0.0-rc1
- BREAKING: `at_utils.dart` no longer exports `PseudoServerSocket` or
  `ApplicationConfiguration` (`app_config.dart`) — import them from the new
  `at_utils_io.dart` barrel.
- BREAKING: `FileLoggingHandler`, `StdErrLoggingHandler`, and `CLILoggingHandler` moved
  to `at_utils_io.dart`; `ConsoleLoggingHandler` is unchanged and stays in `at_utils.dart`.
- BREAKING: `AtSignLogger.stdErrLoggingHandler` (a static convenience field) removed —
  construct `StdErrLoggingHandler()` from `at_utils_io.dart` instead.
- Removed: `AtUtils.formatAtSign` (deprecated since 3.x) — use `AtUtils.fixAtSign`.
```

## Verification

Ran, this release, against `st/at_utils-v4`:

- `dart run wasm_shakedown --package at_utils` — red before this change (config
  named `at_utils_io.dart`, which didn't exist yet), green after: `98 files walked,
  0/0 offenders, 0/0 blocked`.
- `dart run wasm_shakedown --package at_chops` — `0/2 blocked` (ceiling tightened to
  0 in the same commit, per Exit above).
- `dart analyze` clean in `at_utils`; `dart test` — 26/26 passing.
- `dart analyze` clean (0 errors; pre-existing unrelated deprecation infos only) in
  `at_cli_commons`, `at_onboarding_cli`, and the touched files in `at_client` and
  `tests/at_functional_test`.
