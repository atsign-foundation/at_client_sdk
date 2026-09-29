#!/usr/bin/env bash
#
# build_ee.sh — build the Ephemeral Environment image the invitations example
# runs against, from at_server's trunk.
#
# Usage: build_ee.sh [<at_server checkout>]
#   default: the at_server checkout beside this repo
#
# The app runs at pqActive, so it authenticates with ML-DSA APKAM keys, and
# the atServer must verify those. A published EE image that predates that
# support fails every such `pkam:` with an AT0010 RangeError from its RSA
# verifier. This builds from origin/trunk in a temporary worktree, so the
# checkout's own working tree is never touched, using at_server's own
# buildee.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AT_SERVER="${1:-$(cd "$APP_DIR/../../../../.." && pwd)/at_server}"
[[ -d "$AT_SERVER/.git" || -f "$AT_SERVER/.git" ]] \
  || die "no at_server checkout at $AT_SERVER; pass its path"

git -C "$AT_SERVER" fetch -q origin trunk
WORKTREE=$(mktemp -d)/at_server
trap 'git -C "$AT_SERVER" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true' EXIT
git -C "$AT_SERVER" worktree add -q --detach "$WORKTREE" origin/trunk
say "Building $IMAGE from at_server $(git -C "$WORKTREE" rev-parse --short HEAD)"
(cd "$WORKTREE" && bash tools/build_ephemeral_environment/buildee.sh -t "$IMAGE" -q)
ok "built $IMAGE"
