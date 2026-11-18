# Working in this repo

at_client_sdk is the Atsign Dart SDK: foundation packages, a platform-neutral
core (`at_client`) and platform packages, as docs/sdk-shape.md describes.

AGENTS.md at the repo root holds these instructions in full, with the
checks to run before opening a PR.

## Architecture rules come first

docs/architecture/invariants.md outranks every plan, design doc and project
decision record in this repo. A decision binds only when it has a row in
docs/architecture/decisions.md; anything else is a proposal.

If your change would break an invariant, change a guard test, or need a decision with
no row: stop and ask a code owner (.github/CODEOWNERS), in an issue or the PR, before
writing the code. Do not work round the rule, edit the guard, add an `// ignore`, move
the code elsewhere or mark a decision accepted. Say what you needed and where the
existing mechanism fell short. A guard change goes first, in a small PR of its own.

## Use the mechanism that exists

| You need | Use | Never |
|---|---|---|
| An operation to go to the atServer | `useRemoteAtServer` on the request, or `AtClientPreference.remoteLocalPref` for the client | a storage, keystore or queue that connects |
| A client with nothing durable | `InMemoryAtClientStorage` | a storage that is not on the device |
| A connection | the `lookUps` factory the client was given | a connection built inside `at_client` |
| A platform default (storage, transport, routing, replay) | the platform package's builder | a platform preset in `at_client` |
| Platform code | a `*_io.dart` or `*_web.dart` library, or a platform package | `dart:io` reachable from a neutral barrel |
| Something from another package | that package's barrel | `package:<other>/src/...` |
| A collaborator or a client | a required constructor parameter | a new singleton, static field or `AtClientManager.getInstance()` |
| To compare Atsigns or key a cache | `.toAtsign()` on both sides; (`atSign`, `enrollmentId`) | the raw string, or the Atsign alone |
| A public type others extend or implement | `abstract class`, new members with default bodies | `abstract interface class` with no stated reason |
| Behaviour that differs by store | a dartdoc naming the stores, as `NotificationReplay`'s does | a silent difference |
| To add key material | `WrittenAtKeysIo.update` | a read, mutate and `flush` |

A new mode, seam implementation (storage, transport, keys I/O, atDirectory
lookup, crypto provider, `Secondary`), public type or preset needs a decisions
row first, naming the existing mechanism you could not use and why.

## When you review

Before looking for defects, list every new public type, factory or preset, public
member, seam implementation, mode or option, package or dependency, and changed
guard. Ask these five questions of each, give a verdict (fits, duplicates, wrong
layer, bends the seam, needs a decision), and report that list first:

1. Existing mechanism: what in the codebase, searched by capability, already does this job, and why is it not used?
2. Owning layer: which package should own it, and does it carry a platform, transport, deployment or server concern into a package whose role excludes it?
3. Seam contract: if it implements a seam, does it do the job the seam's dartdoc describes, or a different job through it?
4. Parallel API: does it give app code a second way to do something the public API already does?
5. Written rules: does it conflict with docs/architecture/invariants.md, docs/sdk-shape.md or a dartdoc contract?
