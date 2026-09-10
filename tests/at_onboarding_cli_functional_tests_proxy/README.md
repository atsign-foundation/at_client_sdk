# at_onboarding_cli_functional_tests_proxy

The onboarding-CLI functional tests, run through a proxy rather than straight
at the virtualenv. A second container, `at_proxyserver`, sits in front of the
atServers and the tests reach them through it, so this pack exercises the
`--rootServer proxy:<host>:<port>` form that the sibling pack does not.

## Prerequisites

- Docker Engine and Docker Compose
- this line in `/etc/hosts`: `127.0.0.1       vip.ve.atsign.zone`

  The compose file's `extra_hosts` maps that name inside the containers only.
  The test process dials the proxy by name from the host, so the host needs
  its own answer — without one every connection times out, which reads as a
  broken proxy. `runLocal.sh` checks this before it starts anything.

## Running the tests

```bash
./runLocal.sh 47000
```

The base port is required, and the pack takes the whole `[BASE, BASE+99]`
range: atDirectory at `BASE`, atServers `BASE+1`–`BASE+97`, the proxy at
`BASE+98`, redis at `BASE+99`. Pick a range that does not overlap another
virtualenv — the functional pack defaults to the fixed `64` / `25000-25999`
ports, and the e2e pack's runner takes a base port of its own.

`lib/virtualenv_ports.dart` is the single definition of where those land; the
tests and `check_docker_readiness.dart` both read it, so nothing hard-codes a
port.

To run against a published build instead of the locally built virtualenv:

```bash
VIRTUALENV_IMAGE=atsigncompany/virtualenv:dev_env ./runLocal.sh 47000
```

## Two things the runner does that matter

- **`pkamLoad` is deliberately NOT started.** These tests CRAM-onboard, so they
  need atSigns holding no PKAM key yet. Starting it makes onboarding fail as
  "already activated", which reads like a product bug and is not.
- **It runs `dart test` under a throwaway `HOME`.** at_onboarding_cli falls
  back to `$HOME/.atsign/keys` whenever a preference leaves `atKeysFilePath`
  null, and on a developer machine that holds live personal keyfiles. A demo
  atSign's keyfile left there also outlives the container, and onboarding
  refuses when a keyfile already exists — so the next run fails with "Keys file
  already exists" for an atSign the fresh virtualenv has never onboarded.

CRAM secrets are one-shot, so a re-run needs the virtualenv recycled. The
`docker compose down` at the start of `runLocal.sh` is what makes a second run
work; do not skip it.
