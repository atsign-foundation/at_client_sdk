# decisions.md, the at_client_cli ledger

One ruling per section, numbered permanently, each carrying its status. The
reasoning sits with the ruling; the design that applies them is
[`design.md`](design.md). A ruling that changes is corrected in place and its
status says so; nothing is appended as history.

| Status              | Means                                                                              |
| ------------------- | ---------------------------------------------------------------------------------- |
| `LIVE`              | Stands as ruled.                                                                   |
| `AMENDED`           | Stands, but part was changed later, on the date given.                             |
| `PARTLY SUPERSEDED` | Part was replaced and the rest holds. The body says which part went.               |
| `SUPERSEDED`        | Replaced outright. Title struck.                                                   |
| `REJECTED`          | Considered and not adopted. Title struck; the body stays so it isn't re-proposed.  |

Ruling 1 was made by gkc on 2026-09-13; rulings 2 to 11 on 2026-10-28, when
the design was adopted for at_client 4.0.0.

## 1. at_client_cli ships with the lifecycle majors

`LIVE`. `at_client_cli` 1.0.0 publishes together with the shims
`at_onboarding_cli` 2.0.0 and `at_cli_commons` 4.0.0, so the programs that
must act on the lifecycle's breaking changes act once.

Why: the users who move are the same set either way, and two breaking
releases of at_onboarding_cli in a row ask them twice.

## 2. A new package, with the old two as shims

`LIVE`. Way A of [design section 3](design.md#3-getting-there): the files
move into `packages/at_client_cli` with `git mv`, so their history follows
them, and `at_onboarding_cli` and `at_cli_commons` each publish one last
major that depends on at_client_cli and re-exports it under a deprecated
library. They are discontinued on pub.dev once their known dependents have
moved; that act is gkc's.

Why: pub.dev cannot rename a package, so ways B and C are this one with less
history kept, and neither old package is the natural survivor.

## 3. The design is built in full, in the GA

`AMENDED` 2026-10-28. [Design sections 2 and 4](design.md#2-the-shape) are
built in at_client 4.0.0's release, not merged as is and trimmed later. The
one exception is internal: at_activate's commands become one class per
command behind `AtActivate.main` in an at_client_cli minor after 1.0.0,
with `AuthCliArgs` and `AuthCliCommand` kept as they are.

Why: trimming later is a second breaking release for the same programs,
which ruling 1 exists to avoid. The per-command classes change nothing a
program reaches: programs embed at_activate through `AtActivate.main`, and
noports-tools reads `AuthCliArgs`' flag names and `AuthCliCommand`, which
stay. Rejected: merging both packages unchanged (programs change code
twice); building the design while keeping the `AtOnboardingService` adapter
(its users change code twice); and restructuring at_activate's 1,475 lines
in the GA, which risks the commands for no change a program sees.

## 4. `CLIBase` keeps its name

`LIVE`. 46 files across the sibling repositories call it by name, and its
API does not change. Rejected: renaming it `AtClientCli` behind a deprecated
typedef.

## 5. `AtOnboardingService` ends

`LIVE`. The adapter goes with `AtOnboardingPreference`; a program opens
with `CLIBase` or `Atsign.open`, its keys and store from
[ruling 7](#7-the-keys-and-store-conventions-are-a-small-type-clikeys).
The shims re-export only what at_client_cli keeps, so a program on the
adapter changes code at the bump.

Why: its members are `CLIBase` and `Atsign.open` over again. Measured on
2026-10-28 across 54 repositories (10,033 Dart files):
`AtOnboardingServiceImpl` appears in 21 files in 10 repositories outside
at_client_sdk, more than the draft's count, which walked fewer
repositories. This replaces the client lifecycle's
[ruling 6](../client-lifecycle/decisions.md#6-at_onboarding_cli-keeps-a-three-member-atonboardingservice).

## 6. Four helpers go with no shim

`AMENDED` 2026-10-28. `MySyncProgressListener`, `AuthKeyType`,
`OnboardingUtil` and `createAtClient` leave at_client_cli's API in 1.0.0.
`OnboardingUtil`'s registrar calls stay as at_client_cli's private code behind
`at_register` and `onboard`'s email path, their only users: they are the
free-atSign v3 API (`get-free-atsign`, `register-person`, `validate-person`
and the activation OTP pair), and at_auth's `RegistrarService` makes none of
the first three, being the v4 API with a required API key. They move to
at_auth if the free-atSign flow is wanted outside the CLI.

Why: outside this repository the four have 2, 0, 0 and 1 callers, and only
one of those programs (atGettingStarted, one four-line
`SyncProgressListener`) would not be changing code at the bump anyway.
Rejected: keeping them deprecated in 1.0.0, which needs a 2.0.0 to remove
them; porting the tools to `RegistrarService`, which needs an API key and has
no free-atSign flow; and moving the v3 calls into at_auth now, public API for
one caller.

## 7. The keys-and-store conventions are a small type, `CliKeys`

`AMENDED` 2026-10-28. `CliKeys.fileFor(atSign, {path, passPhrase})` is the
`FileAtKeysIo` at `~/.atsign/keys/<atSign>_key.atKeys`;
`CliKeys.storageFor(atSign, {required program, id = 'single', path})` is a
Hive store the client closes, at `CLIBase`'s
`~/.atsign/storage/<atSign>/<program>/<id>`, and with no `id` it is the
store `CLIBase` opens for that namespace. The free path helpers stay for the
programs that call them. at_activate's own store moves there from
`~/.atsign/at_onboarding_cli/storage/<atSign>/hive`, so a device that ran an
at_onboarding_cli prerelease starts that store afresh; its keys, in the
keyfile, are untouched.

Rejected: keeping at_activate's old path (two conventions live on); free
functions in place of a type; and `'singleton'`, the free path helpers'
default, as the default `id`, since it is not the folder `CLIBase` keeps a
program's store in, so a program moving from `CLIBase` to `Atsign.open`
with `CliKeys` would open an empty store and leave its `local:` records
behind.

## 8. The tools keep their names, and both install paths work

`LIVE`. at_client_cli owns `at_activate` and `at_register`.
`at_onboarding_cli`'s last major keeps two one-line executables that run
at_client_cli's, so `dart pub global activate at_onboarding_cli`, which the
Atsign Protocol specification gives, still installs working tools; the
documentation says `dart pub global activate at_client_cli`. A machine that
activates both gets pub's warning that the executable is already provided,
and the later one wins, running the same code.

Rejected: one `at_client_cli` executable with subcommands (scripts across the
ecosystem call the two names), and no executables in the shim (the old
command would install nothing).

## 9. at_client_cli starts at 1.0.0

`LIVE`. A new package on its own version line; a core major still brings a
major of each platform package. Rejected: 4.0.0 (which reads as if its
majors moved in step with at_client's) and 2.0.0 (continuing
at_onboarding_cli's line).

## 10. `CLIBase` tells a refusal from an outage

`LIVE`. Every refusal throws `AtCredentialRefusedException` naming the atSign
and the cause, whether or not the device has held the atSign online, and an
enrollment awaiting approval says so; an atServer not answering within
`maxConnectAttempts` throws `SecondaryServerConnectivityException`. No client
is left open in either case. The scenarios are
[`cli_base_open.feature`](../../../features/at_client_cli/cli_base_open.feature).

Why: a refusal stands until someone acts, and a retry loop that catches the
outage exception must not keep repeating an open the atServer will keep
refusing. Rejected: keeping `AtOpenRefusedException` for a first-open refusal
(two refusal types for a loop to tell apart), and `AtAuthenticationException`,
the type the removed adapter threw.

## 11. Rulings live here

`LIVE`. This file, in the client lifecycle ledger's shape, with
[`design.md`](design.md) holding the design it applies.
