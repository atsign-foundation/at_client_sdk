# The rollout matrix's programme pair

Two stage-parameterised executables and a shared exchange, compiled twice: once
against this tree's at_client and once against the last **released** one. The
driver that runs them is a test in the functional pack —
`tests/at_functional_test/test/pq_rollout_matrix_test.dart` — so `runLocal.sh`
stays the one entry point and the matrix recycles the virtualenv like every
other live row.

Specified by [`acceptance.md` 16](../../docs/projects/pq/acceptance.md#16-g1--signature-agility-and-the-rollout-matrix);
the layout is ruled in [`decisions.md` 96](../../docs/projects/pq/detail/decisions.md#96-the-programme-pair-gets-a-home-outside-the-workspace-2026-08-14).

## Why three packages

| Package | Resolves at_client | Serves stages |
|---------|--------------------|---------------|
| `scenario/` | whichever arm consumes it | — (library) |
| `current/`  | `../../../packages/at_client` by path | `now`, `rollout1`, `rollout2` |
| `published/`| hosted **3.14.0**, lockfile committed | `published` |

**None of the three is a workspace member.** `packages/at_client` is in the
root `pubspec.yaml` `workspace:` list, so anything inside the workspace
resolves at_client by path — and the control arm has to run what pub.dev
ships. Nesting a standalone package here is established rather than novel:
`packages/at_client/example` is one already.

`published/pubspec.lock` is committed, against a repo-wide `pubspec.lock`
ignore that it is exempted from by name. A control that re-resolves its
transitive set is not a control: a changed result could be a finding or a
different at_commons, with no way to tell which.

## What is shared, and what is not

`scenario/` holds the exchange — the puts, the read-backs, the notification,
the record naming, the line protocol. It compiles against the API surface
**both** at_clients have, and its dependency floor is the released version, so
it cannot reach for anything 3.14.0 lacks.

Exactly two things are arm-specific, and both are arguments the shared code
takes rather than code it contains:

1. **The preference.** `current/` maps the stage name to a `SigningRollout`.
   `published/` cannot: 3.14.0 has no such type, which is precisely what makes
   it a measurement of the released build rather than a simulation of one.
2. **The attach.** `current/` supplies an `AtKeysIo`; 3.14.0's
   `setCurrentAtSign` has no parameter for one. This looks cosmetic and is not
   — `SigningKeyMinting` is inert for a client with no key source, so a
   `rollout2` arm attached without one would mint nothing, publish nothing, and
   pass every cell while measuring an inert client.

That boundary is the point. Two hand-written programs differ for two possible
reasons — at_client changed, or the programs did — and a matrix cannot tell
those apart. One scenario removes the second reason.

## What the matrix covers, and what it does not

The 4×4 is over the **data path**: a real notification, multiple puts and gets.
All sixteen cells pass.

The **signed-envelope** exchange is a `now`/`rollout1`/`rollout2` 3×3, because
a released client and this tree cannot exchange an envelope in either
direction, under any stage — measured, both errors pinned, and accepted rather
than fixed. [`acceptance.md` 16.5](../../docs/projects/pq/acceptance.md#165-the-rollout-matrix)
has the reasoning and
[`decisions.md` 95](../../docs/projects/pq/detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 2 and 3 have the amendment that finding forced.

## Running it by hand

The driver does this for you; by hand, the receiver goes first, because
notification streams are broadcast and do not replay.

```bash
cd tests/pq_matrix/published && dart pub get
cd ../current && dart pub get

# receiver, then sender, against a running virtualenv
dart run current/bin/receiver.dart \
  --stage rollout2 --atsign '@bob🛠' --peer '@alice🛠' \
  --run-id abc123 --storage /tmp/pqm/bob

dart run published/bin/sender.dart \
  --stage published --atsign '@alice🛠' --peer '@bob🛠' \
  --run-id abc123 --storage /tmp/pqm/alice
```

Both write one JSON object per line to stdout, each prefixed `##PQM##`. The
sentinel is there because at_client logs to stdout too, and "the logger is
turned down" is a claim about levels rather than about the stream.
