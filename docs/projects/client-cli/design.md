# at_client_cli: one CLI package, shaped like at_client_flutter

A design for folding `at_onboarding_cli` and `at_cli_commons` into one
package, `at_client_cli`, with the same shape `at_client_flutter` has: the
platform's keys store, the lifecycle behind the platform's UI (here, the
command line), the approving side, and helpers — every path handing back the
`AtClient` the program owns.

## Status

Draft, 2026-09-13. One decision is ruled: **D1, the timing** — gkc ruled on
2026-09-13 that this happens now, as at_onboarding_cli's 2.0: `at_client_cli`
1.0.0 publishes together with the shims `at_onboarding_cli` 2.0.0 and
`at_cli_commons` 4.0.0. The remaining decisions in
[section 6](#6-decisions-to-make) are **paused** until gkc has brought his
colleagues up to speed; nothing is built until they are ruled. The measurements in
[section 1](#1-what-exists-today-measured) were taken on branch
`gkc-client-lifecycle` at the tip that holds at_onboarding_cli 2.0.0-rc1 and
at_cli_commons 3.1.2, against pub.dev's published 1.16.1-rc1 and 3.1.1.

## 1. What exists today, measured

### The two packages

| Package             | In tree     | Newest on pub.dev | Ships                                                                                                                                                                                                                                         |
| ------------------- | ----------- | ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `at_onboarding_cli` | 2.0.0-rc1   | 1.16.1-rc1        | Binaries `at_activate` (15 commands: help, status, onboard, enroll, otp, spp, list, fetch, approve, auto, deny, revoke, unrevoke, delete, interactive) and `at_register`; the `AtOnboardingService` adapter; `AtOnboardingPreference`; registrar HTTP (`OnboardingUtil`, `Register`); `createAtClient`; `AuthCliArgs`; `HomeDirectoryUtil` (unexported); a `ServiceFactoryWithNoOpSyncService` (unexported) |
| `at_cli_commons`    | 3.1.2       | 3.1.1             | `CLIBase` (the standard flags → an open `AtClient`); `getHomeDirectory`, `standardAtClientStoragePath` and the other path helpers; `MySyncProgressListener`; a second `ServiceFactoryWithNoOpSyncService` (exported). Depends on at_onboarding_cli for `AtOnboardingPreference`. |

The two overlap: both build a client from a keyfile and the standard flags
(`CLIBase.fromCommandLineArgs` and `createAtClient`), both carry a no-op sync
factory, both carry home-directory and storage-path helpers
(`HomeDirectoryUtil` and `utils.dart`). Neither has a public entry point for
embedding the `at_activate` command in another binary.

### Who uses what

Counted as files that name the symbol, across a corpus of 823 Dart files:
the sibling repositories on this machine (noports, at_talk, at_nautel_snmp,
ogentic, ZTN_Attalk_Linux_Client, Private_Messaging_Armis, atGettingStarted)
plus this repo's examples and live packs, excluding the two packages
themselves. GitHub adds at_demos, at_tools, at_server, at_python and
at_activate_web as dependents not on this machine. Re-derive with
[section 8](#8-re-deriving-the-figures).

| Symbol                                        | Files | Who                                                                                   |
| --------------------------------------------- | ----- | ------------------------------------------------------------------------------------- |
| `CLIBase`                                     | 23    | this repo's examples and packs 8, atGettingStarted 7, ogentic 3, noports 2, ZTN 2, Armis 1 |
| `getHomeDirectory`                            | 22    | noports 15, at_nautel_snmp 4, ogentic 2, at_talk 1                                    |
| `AtOnboardingPreference`                      | 19    | this repo 10, noports 4, at_nautel_snmp 3, at_talk 2                                  |
| `AtOnboardingServiceImpl` and `.authenticate()` | 14  | this repo's packs 7, at_nautel_snmp 3, noports 2, at_talk 2 (the lifecycle design's ruling 6 counted 7 repositories on GitHub) |
| `standardAtClientStoragePath`                 | 10    | noports 7, ogentic 2, at_talk 1                                                       |
| `createAtClient`                              | 10    | noports 8, this repo 2                                                                |
| `OnboardingUtil` (registrar HTTP)             | 7     | noports 7                                                                             |
| `ServiceFactoryWithNoOpSyncService`           | 7     | noports 6, at_talk 1                                                                  |
| `getDefaultAtKeysFilePath`                    | 6     | noports 6                                                                             |
| `MySyncProgressListener`                      | 6     | this repo 3, noports 2, atGettingStarted 1                                            |
| **`at_activate` embedded by a `src/` import** | 5     | noports, at_talk, ogentic and this repo: `import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli; exit(await auth_cli.main(args));` (atGettingStarted imports the older `src/activate_cli/activate_cli.dart`, removed in 2.0) |
| `getUserName`                                 | 3     | noports 3                                                                             |
| `AuthKeyType`, `printFullParserUsage`, `AtOnboardingException`, `RegisterApiTask` | 0 | nobody outside                                                    |

Two things stand out. Five programs reach into a `src/` path to embed the
activate command, so the most-used capability of `at_onboarding_cli` after
its binary has no public API. And `AtOnboardingPreference` is the one type
that makes `at_cli_commons` depend on `at_onboarding_cli`: what programs use
it for is the CLI's notion of *where the keys and the store are*
(`atKeysFilePath`, `passPhrase`, `storagePath`, `storageFor`) and the
registrar URL.

### What at_client_flutter is, for the mirror

| at_client_flutter                                             | The CLI analogue                                                                              |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| re-exports `at_client`, and `RegistrarService` from at_auth   | the same                                                                                      |
| the platform's keys store: `KeychainAtKeysIo`, `KeychainStorage` | the platform's keys store: `FileAtKeysIo` at the conventional path `~/.atsign/keys/<atSign>_key.atKeys`, with the passphrase; the conventional local-store path |
| the lifecycle behind the platform's UI: `PkamDialog`, `CramDialog`, `ApkamActivationDialog`, `AtSignSelectionDialog` | the lifecycle behind the command line: the standard flags → `open` (today `CLIBase`), and the `onboard` / `enroll` commands |
| the approving side: `EnrollmentRequestList`                   | the approving side: the `list` / `approve` / `deny` / `revoke` / `otp` / `spp` / `auto` commands |
| the registrar: `RegistrarCramDialog`                          | the registrar: `at_register`, and `onboard` fetching a CRAM key by email                     |
| `AtsignFlows`, the seam a test stands in for                  | the same seam, so the commands are testable without an atServer                              |
| `example/` walkthrough, `examples/` apps                      | `example/bin/` programs                                                                       |

## 2. The shape

One package, `packages/at_client_cli`, `package:at_client_cli/at_client_cli.dart`:

```text
lib/at_client_cli.dart          re-exports at_client and RegistrarService; exports everything below
lib/src/keys/                   the file keys store conventions: default keyfile path, passphrase, the local-store path
lib/src/cli_base.dart           CLIBase (unchanged API): the standard flags → an open AtClient
lib/src/commands/               the at_activate commands as a library: activate(args) → exit code, one class per command
lib/src/register/               at_register
lib/src/util/                   getHomeDirectory, getUserName, standardAtClientStoragePath, …; ServiceFactoryWithNoOpSyncService, once
bin/at_activate.dart            calls the library
bin/at_register.dart            calls the library
example/bin/                    the programs at_cli_commons and at_onboarding_cli carry today
```

What an app writes:

```dart
import 'package:at_client_cli/at_client_cli.dart';

// A program with the standard flags: unchanged from at_cli_commons.
final client = (await CLIBase.fromCommandLineArgs(args, namespace: 'my_app')).atClient;

// A program that embeds the activate command, without a src import.
exit(await AtActivate.main(args));

// A program that opens on the conventional keyfile without arg parsing.
final client = await Atsign('@alice').open(
    keys: CliKeys.fileFor('@alice'),          // ~/.atsign/keys/@alice_key.atKeys
    preference: AtClientPreference()..namespace = 'my_app',
    storage: CliKeys.storageFor('@alice'));   // ~/.atsign/storage/...
```

What goes, because at_client has it or nobody uses it: the
`AtOnboardingService` adapter (its three members are `CLIBase` and
`Atsign.open`), `createAtClient` (a second `CLIBase`), `OnboardingUtil`'s
registrar HTTP (at_auth's `RegistrarService` makes the same calls: `getFreeAtSign`, `registerPerson`, `sendActivationOtp`, `verifyActivation`), `AuthKeyType`
(the legacy keyfile field names, which at_auth owns), `AtOnboardingException`
and friends, `printFullParserUsage`, `MySyncProgressListener` (a
`SyncProgressListener` that prints; six files use it, three of them this repo's own examples).
`AtOnboardingPreference` goes with the adapter: its fields are either
`AtClientPreference`'s or the keys-and-store conventions above.

## 3. Getting there

Three ways to arrive at one package; each ends with `at_client_cli` on
pub.dev and the two old names pointing at it.

| Way                                                          | What happens to the old names                                                                                                                                       | Cost to dependents                                                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **A. New package; the old two become shims**                 | `at_onboarding_cli` 2.0.0 and `at_cli_commons` 4.0.0 depend on `at_client_cli` and re-export what they kept; marked discontinued on pub.dev with the replacement named once the known dependents have moved | A dependency bump keeps compiling; the `src/` importers change one import; the adapter's users change one call each |
| **B. Rename `at_cli_commons` in place and fold the CLI in**  | `at_cli_commons` becomes `at_client_cli` (pub.dev cannot rename, so this is A with only one shim); `at_onboarding_cli` becomes the shim                            | The same as A                                                                                                             |
| **C. Rename `at_onboarding_cli` in place and fold commons in** | The reverse of B                                                                                                                                                  | The same as A, and the binaries' home stays where scripts expect it                                                       |

B and C are A with a different amount of git history kept; pub.dev sees a new
name whichever way. The recommendation is A, built by moving the files
(`git mv`) so the history follows them, because `at_onboarding_cli`'s tree
holds the bulk (the commands) and `at_cli_commons` holds the entry point apps
call, and neither is the natural survivor.

The timing question is what the unpublished majors are for. `at_onboarding_cli`
2.0.0-rc1 and `at_cli_commons` 3.1.2 are on this branch and unpublished, and
the lifecycle work already breaks `at_onboarding_cli`'s API. Two orders:

1. **Publish the lifecycle majors first, then do this.** `at_onboarding_cli`
   2.0.0 ships as designed (ruling 6's adapter and all), `at_client_cli` 1.0.0
   follows, and the shims are `at_onboarding_cli` 3.0.0 and `at_cli_commons`
   4.0.0. Two breaking releases of `at_onboarding_cli` in a row for its users.
2. **Make this the 2.0.** `at_client_cli` 1.0.0 and the shims
   `at_onboarding_cli` 2.0.0 / `at_cli_commons` 4.0.0 publish together, from
   this branch or the one after it. One breaking release; the migration table
   already written for 2.0 gains a column. The at_onboarding_cli functional
   packs and the noports port move in the same change.

The recommendation is 2, because the users who must act are the same set
either way and asking them twice costs more than the time it adds to this
branch. That is a decision for gkc ([section 6](#6-decisions-to-make), D1).

## 4. What moves where

| From                                                              | To                                             | Note                                                                                           |
| ----------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `at_cli_commons/lib/src/cli_base.dart`                            | `lib/src/cli_base.dart`                        | API unchanged; `preference:` takes `AtClientPreference`; keys and store come from the conventions |
| `at_cli_commons/lib/src/utils.dart`                               | `lib/src/util/`                                | unchanged                                                                                      |
| `at_cli_commons/lib/src/service_factories.dart`                   | `lib/src/util/`                                | the one copy; at_onboarding_cli's unexported twin goes                                          |
| `at_cli_commons/lib/src/sync_listener.dart`                       | removed                                        | six files, three of them this repo's examples; a `SyncProgressListener` is four lines          |
| `at_onboarding_cli/lib/src/cli/auth_cli*.dart`                    | `lib/src/commands/`                            | `main` becomes `AtActivate.main(args)`, public; one class per command behind it                |
| `at_onboarding_cli/lib/src/register_cli/`, `util/register_api_*` | `lib/src/register/`                            | `at_register`                                                                                  |
| `at_onboarding_cli/lib/src/util/at_onboarding_preference.dart`   | `lib/src/keys/`                                | the keys-and-store conventions (`atKeysFilePath`, `passPhrase`, `storagePath`, `storageFor`) as a small type; the rest is `AtClientPreference` |
| `at_onboarding_cli/lib/src/util/home_directory_util.dart`        | merged into `lib/src/util/`                    | one home-directory helper                                                                      |
| `at_onboarding_cli/lib/src/onboard/`                              | removed                                        | the adapter; ruling 6's callers move to `CLIBase` or `Atsign.open` at the bump                 |
| `at_onboarding_cli/lib/src/util/create_at_client_cli.dart`       | removed                                        | `CLIBase`                                                                                      |
| `at_onboarding_cli/lib/src/util/onboarding_util.dart`            | removed                                        | at_auth's `RegistrarService`; `onboard`'s email path calls it                                  |
| `at_onboarding_cli/lib/src/util/{auth_key_type,at_onboarding_exceptions,print_full_parser_usage}.dart` | removed | no callers outside                                                                     |
| `tests/at_onboarding_cli_functional_tests*`                       | `tests/at_client_cli_functional_tests*`        | the packs, their CI jobs in `at_libraries.yaml`, and the `runLocal.sh` runners                 |
| `.github/workflows/at_libraries.yaml` matrix entries              | one entry                                      |                                                                                                |

## 5. Migration for programs

```dart
// at_cli_commons → at_client_cli: one import
import 'package:at_client_cli/at_client_cli.dart';
final client = (await CLIBase.fromCommandLineArgs(args)).atClient;   // unchanged

// Embedding at_activate: a public entry point instead of a src import
import 'package:at_client_cli/at_client_cli.dart';
Future<void> main(List<String> args) async => exit(await AtActivate.main(args));

// AtOnboardingServiceImpl: the adapter's three members
final svc = AtOnboardingServiceImpl('@alice', pref)..authenticate();   // before
final client = await Atsign('@alice').open(                          // after
    keys: CliKeys.fileFor('@alice', passPhrase: pass),
    preference: AtClientPreference()..namespace = 'my_app',
    storage: CliKeys.storageFor('@alice'));

// AtOnboardingPreference: the conventions, not a preference
final pref = AtOnboardingPreference()..atKeysFilePath = p..storagePath = s;   // before
final keys = FileAtKeysIo(filePath: (_) => p);                              // after
final storage = HiveAtClientStorage(atSign: '@alice', storagePath: s, closedByClient: true);
```

## 6. Decisions to make

| Id | Question                                                                                          | Recommendation                                                                                                                                                              |
| -- | ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1 | Do this before the lifecycle majors publish (one breaking release of at_onboarding_cli), or after (two)? | **Ruled 2026-09-13: before.** `at_client_cli` 1.0.0 and the shims `at_onboarding_cli` 2.0.0 / `at_cli_commons` 4.0.0 publish together; the same users act once.       |
| D2 | Way A, B or C in [section 3](#3-getting-there)?                                                   | A, with `git mv` so history follows the files.                                                                                                                              |
| D3 | The entry point's name: keep `CLIBase`, or a name that mirrors the dialogs (`AtClientCli`)?      | Keep `CLIBase`: 19 files call it by name and its API does not change. A typedef for a new name costs nothing later.                                                        |
| D4 | The binaries: keep `at_activate` and `at_register`, or one `at_client_cli` binary with subcommands? | Keep both names; scripts and READMEs across the ecosystem invoke them. The library entry points are what change.                                                            |
| D5 | Does `AtOnboardingService` survive as a shim member, or end with ruling 6's callers moving?       | End it in the shim generation: the shim re-exports `at_client_cli`, and the adapter's 5 call sites move to `open` or `CLIBase` at the bump; ruling 6 is amended to say so. |
| D6 | The keys-and-store conventions: a small type (`CliKeys`), or free functions beside `getHomeDirectory`? | A small type with the two builders and the passphrase, so a program has one place to look; the existing free path helpers stay for the 10 files that use them.           |
| D7 | Drop `MySyncProgressListener`, `AuthKeyType`, `OnboardingUtil`, `createAtClient` outright, or shim them for one release? | Drop them all: `RegistrarService` already makes `OnboardingUtil`'s four calls, and none of the others has a caller a dependency bump cannot fix.                          |
| D8 | Where the design and rulings live once ruled                                                       | `docs/projects/client-cli/` with a `decisions.md` in the lifecycle ledger's shape, and a pointer row in the PQ plan's P1 band while it is in flight.                       |

## 7. Relationship to the other plans

- [The client lifecycle](../client-lifecycle/design.md): its ruling 6 kept
  a three-member `AtOnboardingService`; D5 asks whether that adapter ends
  here. Its "what each package keeps" section names `at_onboarding_cli` and
  `at_cli_commons` separately and is amended when this is ruled.
- The deprecation-debt plan (`docs/projects/deprecations/plan.md`): the
  packages an application depends on directly do not break in that pass;
  this is a deliberate major with a migration, not debt.
- The PQ plan's rollout: `--posture` inherits at_client's default on every
  command today; nothing here changes that.

## 8. Re-deriving the figures

```sh
# symbol use outside the two packages, across the sibling repos on this machine
for s in getHomeDirectory CLIBase AtOnboardingPreference standardAtClientStoragePath createAtClient OnboardingUtil ServiceFactoryWithNoOpSyncService AtOnboardingServiceImpl MySyncProgressListener; do
  printf '%s: ' "$s"; grep -rl "$s" ~/dev/atsign/repos/{sshnoports/packages,at_talk,at_nautel_snmp,ogentic,ZTN_Attalk_Linux_Client,Private_Messaging_Armis,atGettingStarted} \
    ~/dev/atsign/repos/at_client_sdk/packages/at_client/example --include='*.dart' 2>/dev/null | grep -v '/.dart_tool/\|at_onboarding_cli/\|at_cli_commons/' | wc -l
done
# the src importers
grep -rl "at_onboarding_cli/src/" ~/dev/atsign/repos --include='*.dart' | grep -v '/.dart_tool/\|at_client_sdk/'
# dependents on GitHub
gh search code at_onboarding_cli --owner atsign-foundation --filename pubspec.yaml --json repository --jq '.[].repository.nameWithOwner' | sort -u
```
