# at_map

Dev-only generator and gate for the SDK map in `docs/map`. Not published; run
by `dart run at_map` from anywhere in the workspace, and by the `map` job in
`.github/workflows/at_client_sdk.yaml`. The design is
[`docs/projects/sdk-map/design.md`](../../docs/projects/sdk-map/design.md),
and the scenarios are
[`features/at_map/sdk_map.feature`](../../features/at_map/sdk_map.feature).

```bash
dart run at_map build                # write docs/map/data/core.js and flows/*
dart run at_map build --indexes      # write docs/map/data/indexes.js alone
dart run at_map check                # the map job's gate
dart run at_map check --server DIR   # what moving the pin to DIR would change
dart run at_map bless FLOW.STEP...   # record a step's body as reviewed
dart run at_map diff-prod            # steps that differ at the production tag
```

Every command reads at_server at the SHA `docs/map/model/roots.yaml` pins,
from a clean checkout at that SHA with `dart pub get` run in
`packages/at_secondary_server`, and with its full history and tags. Pass it as
`--server-repo DIR`, or set `AT_MAP_SERVER_REPO`; the default is `../at_server`
beside this checkout:

```bash
git clone https://github.com/atsign-foundation/at_server.git /tmp/at_server
git -C /tmp/at_server checkout --detach "$(awk '/^server:/ {s=1} s && /^  sha:/ {print $2; exit}' docs/map/model/roots.yaml)"
(cd /tmp/at_server/packages/at_secondary_server && dart pub get --enforce-lockfile)
dart run at_map check --server-repo /tmp/at_server
```

`diff-prod` refuses to run when `CI` is set, and `check --server` prints only
counts there: both would otherwise name steps in a public log.

The tests need the same checkout through `AT_MAP_SERVER_REPO`, and Chrome for
the page tests (`CHROME_EXECUTABLE`, or an installed Chrome or Chromium):

```bash
AT_MAP_SERVER_REPO=/tmp/at_server dart test --concurrency=1
```
