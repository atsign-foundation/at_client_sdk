# The released peer

One package and one program: at_client **3.14.0**, resolved from pub.dev, asked
what it makes of an enrollment's `_apsk`.

That is the whole of what survives here, and it survives for one reason — no
single process can hold two versions of one package, and the only authority on
what a *deployed* peer can parse is a deployed peer. The test that drives it is
`tests/at_functional_test/test/pq_released_peer_test.dart`, so `runLocal.sh`
stays the one entry point.

⚠️ **This was a 4×4 rollout matrix, and it is not one any more.** It ran every
cell as two spawned processes talking over a `##PQM##` line protocol, because
the `published` column had to be a different build from the other three. The
posture grid replaced it — `tests/at_functional_test/test/pq_posture_grid_test.dart`
— and runs in **one process**, which it can precisely because it no longer has
a released arm among its cells. Deleted with the matrix: the whole exchange
(puts, gets, a notification), both stage-parameterised programme arms, the line
protocol, and the driver that spawned them.

## Why two packages for one program

| Package | Resolves at_client | Holds |
|-------------|--------------------------|--------------------------------------|
| `scenario/` | whatever consumes it | the reader, and the demo-key connect |
| `published/`| hosted **3.14.0**, locked | the entrypoint and its preference |

**Neither is a workspace member.** `packages/at_client` is in the root
`workspace:` list, so anything inside the workspace resolves at_client by path
— and this arm has to run what pub.dev ships.

`published/pubspec.lock` is committed, against a repo-wide `pubspec.lock`
ignore it is exempted from by name. A control that re-resolves its transitive
set is not a control: a changed result could be a finding or a different
at_commons, with no way to tell which.

The reader lives in `scenario/` rather than in `published/` so that it compiles
against **both** at_clients. Its mixin members are declared identically in
3.14.0 and in this tree, which is what makes a divergence attributable to
at_client rather than to two hand-written programs.

## Running it by hand

```bash
cd tests/pq_matrix/published && dart pub get

dart run bin/read_apsk.dart \
  --atsign '@alice🛠' --peer '@alice🛠' \
  --peer-enrollment-id <the enrollment whose _apsk you want read> \
  --namespace wavi --root-domain vip.ve.atsign.zone --root-port 64 \
  --storage /tmp/relpeer --run-id byhand
```

It writes one JSON object to stdout prefixed `##APSK##`. The sentinel is there
because at_client logs to stdout too, and "the logger is turned down" is a
claim about levels rather than about the stream.

It reports and decides nothing. The verdict — that a `pqReady` advertisement is
indistinguishable from a `legacy` one to a deployed peer, and that a `pqActive`
one is not — is asserted by the test that spawns it, because a probe that
judges its own output has an invisible failure mode.
