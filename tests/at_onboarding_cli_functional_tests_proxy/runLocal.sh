#!/usr/bin/env bash
set -euo pipefail

# Run the onboarding-CLI *proxy* functional suite locally, the way CI runs it
# (.github/workflows/at_libraries.yaml, functional_tests_at_onboarding_cli,
# matrix entry at_onboarding_cli_functional_tests_proxy).
#
# It is a sibling of tests/at_onboarding_cli_functional_tests/runLocal.sh and
# shares its two rules, for the same reasons:
#
#  1. pkamLoad is NOT started. These tests CRAM-onboard, so they need atSigns
#     holding no PKAM key yet. Starting it makes onboarding fail as "already
#     activated", which reads like a product bug and is not.
#  2. check_test_env.dart is NOT run - this pack does not ship one, and the
#     sibling's would hang anyway: it polls for state only pkamLoad creates.
#     CI runs readiness, then a sleep, then the tests.
#
# What differs from the sibling: a second container, at_proxyserver, sits in
# front of the virtualenv and the tests reach the atServer through it
# (--rootServer proxy:vip.ve.atsign.zone:<proxy port>). So this pack needs one
# more host port than its siblings: BASE+98, or 443 on an unshifted run.
# `virtualenvProxyPort` in lib/virtualenv_ports.dart is the one definition of
# that, and the tests and the readiness check both read it.
#
#     To match CI exactly, or to measure against a published build on purpose:
#
#         VIRTUALENV_IMAGE=atsigncompany/virtualenv:dev_env ./runLocal.sh
#         VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip     ./runLocal.sh
#
# NOTE: tests that spawn at_activate must pass the root port to the child. It
# builds its own client and defaults to 64, so a base-port run hangs to timeout
# with nothing red. runCliCommand supplies it.
#
# CRAM secrets are one-shot: a second run against a virtualenv that already
# onboarded these atSigns fails. The compose down below is what makes a re-run
# work, so do not skip it.

cd "$(dirname "$0")"

if [[ -z "${1:-}" ]]; then
  echo "*** You must supply a BASE_PORT"
  exit 1
fi
BASE_PORT="$1"

# The whole [BASE, BASE+99] range, assigned once. The atServers stop at +97
# because the proxy takes +98 and redis +99; an earlier version of this block
# handed +98 to both the top atServer and the proxy, and only survived because
# a second copy of the block overwrote it further down.
export VIRTUALENV_BASE_PORT="$BASE_PORT"
export VE_ROOT_PORT="$BASE_PORT"
export VE_SECONDARY_LOW=$((BASE_PORT + 1))
export VE_SECONDARY_HIGH=$((BASE_PORT + 97))
export VE_PROXY_PORT=$((BASE_PORT + 98))
export VE_REDIS_PORT=$((BASE_PORT + 99))
echo "*** Using base port ${BASE_PORT}: atDirectory ${VE_ROOT_PORT}," \
     "atServers ${VE_SECONDARY_LOW}-${VE_SECONDARY_HIGH}," \
     "proxy ${VE_PROXY_PORT}, redis ${VE_REDIS_PORT}"

echo "*** Getting dependencies" && dart pub get

export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"
echo "*** Using image ${VIRTUALENV_IMAGE}"

echo "*** docker compose -f local-compose.yaml down" && docker compose -f local-compose.yaml down
# A locally built image is on no registry, so pulling it fails the run.
if [[ "$VIRTUALENV_IMAGE" == *"/"* ]]; then
  echo "*** docker compose -f local-compose.yaml pull" && docker compose -f local-compose.yaml pull
else
  echo "*** docker compose pull SKIPPED (local image ${VIRTUALENV_IMAGE})"
fi
echo "*** docker compose -f local-compose.yaml up -d" && docker compose -f local-compose.yaml up -d

# The compose file's `extra_hosts` maps this name inside the containers only.
# The test process dials the proxy BY NAME from the host, so the host needs its
# own answer - and without one every connect times out, which reads as the
# proxy being broken rather than as a missing hosts entry.
echo "*** Checking the host resolves vip.ve.atsign.zone"
if ! getent hosts vip.ve.atsign.zone >/dev/null 2>&1 \
    && ! dscacheutil -q host -a name vip.ve.atsign.zone 2>/dev/null \
       | grep -q '^ip_address:'; then
  echo "!!! vip.ve.atsign.zone does not resolve on this host."
  echo "!!! The tests dial the proxy by that name, so every connection would"
  echo "!!! time out and look like a broken proxy. Add to /etc/hosts:"
  echo "!!!     127.0.0.1 vip.ve.atsign.zone"
  exit 1
fi

echo "*** Checking docker readiness" && dart run check_docker_readiness.dart

echo "*** Waiting 10s for the atSigns to come up" && sleep 10

echo "*** Clearing client test storage"
rm -rf test/hive
find test -name '*.atKeys' -delete 2>/dev/null || true

# at_onboarding_cli falls back to $HOME/.atsign/keys - the real one - whenever
# a preference leaves atKeysFilePath null or an auth_cli invocation omits -k,
# and on a developer machine that directory holds live personal keyfiles. Tests
# take their paths from test/utils/test_keys_dir.dart instead; this is the
# backstop for anything that slips through. A demo-atSign keyfile left in the
# real directory outlives the container the compose down above just recycled,
# and onboarding refuses when a keyfile already exists, so the next run fails
# with "Keys file already exists" for an atSign the fresh virtualenv has never
# onboarded - which reads as a product bug and is not. With a throwaway HOME
# such a keyfile lands beside it and goes when it does, and the real
# ~/.atsign/keys is neither written nor read.
#
# Scoped to `dart test` deliberately - docker reads its context from the real
# $HOME/.docker and pub its cache from $HOME/.pub-cache, so neither moves.
REAL_HOME="$HOME"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.atsign/keys"
echo "*** Throwaway HOME for this run: $TEST_HOME"

echo "*** Running tests"
# Let the run fail through to cleanup, then propagate its code - otherwise
# set -e aborts before teardown on the very failure this exists to catch.
set +e
HOME="$TEST_HOME" PUB_CACHE="${PUB_CACHE:-$REAL_HOME/.pub-cache}" \
dart test --concurrency=1 -r expanded
TEST_EXIT=$?
set -e

echo "*** docker compose -f local-compose.yaml down" && docker compose -f local-compose.yaml down

exit "$TEST_EXIT"
