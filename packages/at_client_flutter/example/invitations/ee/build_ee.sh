#!/usr/bin/env bash
#
# build_ee.sh — build an Ephemeral Environment image from an at_server
# checkout, to run the invitations example against atServer changes that are
# not on trunk yet.
#
# Usage: build_ee.sh [<at_server checkout> [<ref>]]
#   default: the at_server checkout beside this repo, at origin/trunk
#
# up.sh uses the published atsigncompany/ephemeral:dev_env, built from trunk,
# unless INV_EE_IMAGE names another. This builds at_ephemeral:invitations, so
# run INV_EE_IMAGE=at_ephemeral:invitations ee/up.sh to use it. It builds in a
# temporary worktree, so the checkout's own working tree is never touched,
# using at_server's own buildee.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AT_SERVER="${1:-$(cd "$APP_DIR/../../../../.." && pwd)/at_server}"
REF="${2:-origin/trunk}"
IMAGE="at_ephemeral:invitations"
[[ -d "$AT_SERVER/.git" || -f "$AT_SERVER/.git" ]] \
  || die "no at_server checkout at $AT_SERVER; pass its path"

git -C "$AT_SERVER" fetch -q origin
WORKTREE=$(mktemp -d)/at_server
trap 'git -C "$AT_SERVER" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true' EXIT
git -C "$AT_SERVER" worktree add -q --detach "$WORKTREE" "$REF"
say "Building $IMAGE from at_server $(git -C "$WORKTREE" rev-parse --short HEAD)"
(cd "$WORKTREE" && bash tools/build_ephemeral_environment/buildee.sh -t "$IMAGE" -q)
ok "built $IMAGE"
