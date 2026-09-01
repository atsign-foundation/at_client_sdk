# sdk.md — the at_client_sdk workspace: packages, release train, toolchain, test harnesses

Format and rules: [`README.md`](README.md).

## Test harnesses — the virtual environment

### `at_virtual_env:local` and `at_ephemeral:local` are different environments built by different tools

**Is:** the **virtual environment (VE)** is what every at_client_sdk live pack
talks to; the **ephemeral environment (EE)** is a separate thing. They are built
from separate trees in the at_server repo and carry separate tags:

| | built from | tag |
|---|---|---|
| VE | `tools/build_virtual_environment/ve/Dockerfile`, over `ve_base/Dockerfile` | `at_virtual_env:local` |
| EE | `tools/build_ephemeral_environment/buildee.sh` | `at_ephemeral:local` |

`buildee.sh` says so in its own header — *"build an ephemeral environment (EE)
image from THIS working tree"*. It is the better-instrumented of the two and the
obvious thing to reach for, which is exactly why it gets offered when what is
wanted is a VE. `ve/Dockerfile.vip` and `ve/Dockerfile.canary_to_vip` exist but
are not on the local-build path.

`tools/build_virtual_environment/install_PKAM_Keys/` is the `pkamLoad` step whose
presence or absence distinguishes the live packs' runners.

**Matters because:** a request for "a build of the environment" answered with the
EE produces an image the packs never load, and no error says so — the packs go on
using whatever `at_virtual_env:local` already held.

**Evidence:** `at_server` `tools/build_ephemeral_environment/buildee.sh:3` and its
`-t` default; `tools/build_virtual_environment/ve/Dockerfile`;
`at_server` `tests/at_functional_test/runLocal.sh:75`.
**Checked:** `at_server origin/trunk @ 45846a7b`, 2026-09-01

### Nothing in at_client_sdk builds the VE image; three at_server runners rebuild it unconditionally

**Is:** all three at_client_sdk runners — `tests/at_functional_test/runLocal.sh`,
`tests/at_end2end_test/runLocal.sh`,
`tests/at_onboarding_cli_functional_tests/runLocal.sh` — contain **zero**
`docker build` lines. They default `VIRTUALENV_IMAGE` to `at_virtual_env:local`
and skip `docker compose pull` for it, because a local image is on no registry.

In **at_server**, three scripts `docker build -t at_virtual_env:local`
unconditionally on every run: `tests/at_functional_test/runLocal.sh:75`,
`tests/at_end2end_test/runLocal.sh:135`, and
`tests/at_functional_test/runDualCompare.sh:62`.

⚠️ The relative paths `tests/at_functional_test/runLocal.sh` and
`tests/at_end2end_test/runLocal.sh` exist in **both** repos, so a claim about
"the runner at that path" is ambiguous until the repo is named.

**Matters because:** the tag is a shared mutable name on one Docker daemon with a
single writer that is not us. Whoever ran at_server's tests last decides which
server our live packs are talking to, and nothing we run changes it. A pack that
went green may have been measuring a server nobody intended.

**Evidence:** `tests/at_functional_test/runLocal.sh:47,52-55` in this repo
(`VIRTUALENV_IMAGE` default and the skipped pull); the three at_server lines
above.
**Checked:** at_client_sdk `b566b6759` and `at_server origin/trunk @ 45846a7b`,
2026-09-01

### The VE image's OCI labels are inherited from its base and name the wrong commit

**Is:** the VE `docker build` passes no `--label`, so the image inherits the
label set of `atsigncompany/vebase:latest`. Read on this daemon, the image under
`at_virtual_env:local` reported:

```
org.opencontainers.image.revision = 6940764672e028c59ac4d5407668cb423ee25dec
org.opencontainers.image.title    = at_server
org.opencontainers.image.description = Base image for Atsign Virtual Environment
org.opencontainers.image.created  = 2026-08-31T07:01:58.036Z
```

while the image's own `.Created` was `2026-08-31T18:40:38.302Z`. That revision is
a **real merge commit on at_server trunk** (`Merge pull request #2777`), not the
commit the binaries inside were compiled from.

Two tells that the label set is inherited rather than the image's own:
`description` still reads *"Base image for …"*, and the `created` **label lags
the image's `.Created`** — 11h38m here. An inherited label cannot postdate the
image it labels.

⛔ Neither tell is a verdict on the revision: a build that overrides *only*
`revision` leaves `created` inherited and still lagging, so the pair rejects an
image whose revision is correct. `buildee.sh` is that shape — it sets `revision`,
`source`, `com.atsign.ee.branch`, `com.atsign.ee.platform` and no `created`.
A label in a namespace no upstream base uses (`com.atsign.ve.*`) is the only
structurally uninheritable answer.

**Matters because:** this is worse than an unlabelled image. It answers
confidently, plausibly, and wrongly — a genuine, current, on-trunk sha — so a
provenance check written the obvious way concludes "known-good trunk build" about
an image that is neither trunk nor any committed branch.

**Evidence:** `docker image inspect at_virtual_env:local --format '{{json .Config.Labels}}'`
and `--format '{{.Created}}'`; `git -C ../at_server rev-list --parents -n1 69407646`
returns three words (a merge) and `git merge-base --is-ancestor 69407646 origin/trunk`
succeeds. `buildee.sh:87-90` for the label set it does apply.
**Checked:** at_client_sdk `b566b6759`, `at_server origin/trunk @ 45846a7b`,
2026-09-01. The image read was the one present on this machine that day; its
labels move when at_server rebuilds.
