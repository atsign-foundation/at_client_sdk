---
name: at-client-skills-cli
description: >
  Use this skill when building a Dart command-line program, daemon, server,
  IoT program or headless agent on the Atsign Platform with at_client_cli, or
  upgrading one from at_onboarding_cli or at_cli_commons. Covers CLIBase
  argument parsing and authentication, CliKeys keyfiles and storage, one store
  per process, onboarding and enrolling atsigns with at_activate, enrolling a
  headless device and approving enrollments from an agent, coordinating
  several instances of one agent with a server mutex, and stateless instances
  with no sync. Use alongside at-client-skills-core, which covers collections,
  notifications, sync, RPC and errors.
license: BSD-3-Clause
compatibility: Claude Code and any agentskills.io-compatible agent.
user-invocable: true
metadata:
  version: "2.0.0"
  last_modified: "Fri, 27 Nov 2026 12:38:51 GMT"
---

# Atsign Platform: CLI, daemons and headless agents

> **Audience:** developers building a Dart program with no UI on the Atsign
> Platform — a CLI, daemon, server, IoT program or agent.

This skill covers what is specific to a program with no UI. What the program
does with its client — collections, notifications, sync, RPC, errors, the
lifecycle — is in **at-client-skills-core**; use the two together. If it is
not among your skills, ask the developer to install it: `dart run skills get
--skill at-client-skills-core`.

---

## 1. Rules

- **The package:** `dart pub add at_client_cli`, imported as
  `package:at_client_cli/at_client_cli.dart`.
- **Where the posture slips:** `CLIBase` given no `preference:` runs at the
  SDK's default, `legacy`, and says nothing; so does `at_activate` run
  without `--posture pqActive`.
- **Upgrading from at_onboarding_cli or at_cli_commons?** Their code lives in
  `at_client_cli`; at-client-skills-core's upgrade guide and deprecation guide
  map each old type to its replacement.

---

## 2. Authenticate with `CLIBase`

Don't hand-roll `.atKeys` loading and PKAM auth. `CLIBase` does argument
parsing, key loading, authentication and client setup in one call:

```dart
import 'package:at_client_cli/at_client_cli.dart';

void main(List<String> args) async {
  final AtClient atClient =
      (await CLIBase.fromCommandLineArgs(args,
              namespace: 'my_app',
              preference: AtClientPreference(posture: PqPosture.pqActive)))
          .atClient;
  // ready — collections, notifications, RPC all work from here
}
```

`CLIBase.argsParser` provides the standard flags: `-a` atsign, `-k` path to
the `.atKeys` file, `-n` namespace if not fixed in code, `-s` storage
directory, verbose, `--never-sync`, and more.

`CLIBase` waits for the client to come online, and otherwise stops it and
throws:

<!-- pyml disable-num-lines 6 md013-->
| Exception | Means | Retry? |
| --- | --- | --- |
| `AtCredentialRefusedException` | the atServer refused the keys | no — a person |
| `SecondaryNotFoundException` | the atDirectory has no atServer for the atsign | no — a person |
| `SecondaryServerConnectivityException` | the atServer was not reached in time | yes |
| `FormatException` (`ArgParserException`) | a flag is missing or malformed, before anything connects | no — print the usage and exit |

It can also throw what opening a client throws, such as
`AtNoCredentialException` and `AtStorageInUseException`: core's lifecycle
reference (section 1) lists them. Catch each in `main` and print one line and
a non-zero exit, not a stack trace.

`CLIBase` takes `lookUps:`; with none it uses `lookUpsFor` (§3).

A keyfile holding only an enrollment request is resumed: `CLIBase` waits for
its approval, as `at_activate` does, and throws `AtEnrollmentException` when
it is denied or expires.

> **Gotcha:** `exit()` does not flush buffered stdout — `await
> stdout.flush()` first, or log lines vanish when output is redirected.

---

## 3. Opening a client yourself

Without `CLIBase`, open with the `Atsign` verbs and at_client_cli's pieces:

```dart
final prefs = AtClientPreference(posture: PqPosture.pqActive)..namespace = 'my_app';
final client = await Atsign(atSign).open(
    keys: CliKeys.fileFor(atSign, path: keysPath),
    preference: prefs,
    storage: CliKeys.storageFor(atSign, program: 'my_app', path: dir),
    lookUps: lookUpsFor(prefs.rootDomain),
    secondaryAddressFinder:
        CacheableSecondaryAddressFinder(prefs.rootDomain, prefs.rootPort));
// ... and `await client.stop()` when the program is done.
```

- `CliKeys.fileFor(atSign, path:, passPhrase:)` is the keyfile, by default
  `~/.atsign/keys/<atSign>_key.atKeys`. It locks the keyfile while it
  retrofits post-quantum keys, so instances sharing one take turns.
- `CliKeys.storageFor(atSign, program:, path:)` is a `HiveAtClientStorage`
  the client closes when it stops.
- `lookUpsFor(preference.rootDomain)` builds every connection: TLS on TCP, or
  a proxy for a root domain of the form `proxy:host:port`.
- `createAtClient(atSign:, atKeysFilePath:, ...)` is the client
  `at_activate`'s commands open: from the keyfile, syncing nothing, on a
  store of its own.
- `StdErrLoggingHandler`, `FileLoggingHandler` and `CLILoggingHandler` route
  the SDK's logging.

---

## 4. One process, one store

Every process needs its own store (core's lifecycle reference, section 2).
`CLIBase` keeps it under
`~/.atsign/storage/<atSign>/<namespace>/single/`. When launching several
instances of one program on a machine, give each a unique directory
(`Directory.systemTemp.createTempSync('agent_')`) and pass it as `-s`. Each
instance must `await client.stop()` when it exits, or the next process to
claim that path is refused.

---

## 5. Onboarding and enrollment from a terminal

`at_activate` (from `at_client_cli`) onboards and enrolls atsigns. Pass every
command `--posture pqActive`, `approve`, `deny`, `revoke` and `auto`
included. Onboarded that way, the keyfile holds a post-quantum credential
from the start, so no instance has to retrofit it.

`at_register` gets a free atsign. It, and `at_activate onboard` without `-c`,
send the registrar API key in `AT_REGISTRAR_API_KEY` when it is set, and
otherwise a built-in key. Install both with `dart pub global activate
at_client_cli`.

## 6. Enrolling and approving devices

A device with no screen enrolls with `Atsign(...).enroll(...)`, and an
always-on agent holding `__manage` can approve other devices' requests.
at-client-skills-core's lifecycle reference (section 8) has the passcode, the
wait for a decision and the approver rules;
[references/multi-agent.md](references/multi-agent.md) has the approving
agent.

---

## 7. Several instances of one agent

<!-- pyml disable-num-lines 5 md013-->
| Instances… | Pattern |
| --- | --- |
| Keep state / use collections | A server mutex per task: `atClient.tryAcquireServerMutex(key, ttl: …)` |
| Stateless request/response workers | No-op sync + remote operations |
| N instances of one `AtRpc` server | `AtRpc.server(enableRequestMutex: true)` |

- `tryAcquireServerMutex` returns null when another instance holds the lock,
  and throws any other failure. It needs an atServer from p3.13.0.
- Stateless instances open with `serviceFactory:
  ServiceFactoryWithNoOpSyncService()` (from `at_client_cli`, not
  `at_client`; `CLIBase`'s `--never-sync` does the same) **and**
  `remoteLocalPref = RemoteLocalPref.remoteOnly` — with sync off, a local
  write would never leave the machine.
- The mutex coordinates work, not storage: each instance still needs its own
  store (§4).

Read [references/multi-agent.md](references/multi-agent.md) for the mutex
lease, ttl and atServer-version rules, the stateless pattern in full, and
approving enrollments from an agent.
