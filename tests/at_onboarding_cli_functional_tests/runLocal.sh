#!/usr/bin/env bash
set -euo pipefail

# Run the onboarding-CLI functional suite locally.
#
#   ./runLocal.sh            # legacy fixed ports (64 / 25000-25999 / 6379)
#   ./runLocal.sh 47000      # base port: atDirectory 47000, atServers 47001-47098
#
# A BASE_PORT shifts the virtualenv into a [BASE, BASE+99] range so it can run
# alongside another virtualenv on a different base port. docker-compose.yaml
# reads VIRTUALENV_BASE_PORT and maps that whole range; the tests read the same
# variable through `test/utils/virtualenv_ports.dart`, because every site that
# names vip.ve.atsign.zone must also name the port.
#
# Deliberately NOT a copy of tests/at_functional_test/runLocal.sh. Two
# differences matter:
#
#  1. pkamLoad is NOT started. That script installs PKAM public keys for the
#     demo atSigns, and these tests CRAM-onboard - they need atSigns that hold
#     no PKAM key yet. Starting it makes onboarding tests fail as "already
#     activated", which reads like a product bug and is not.
#  2. The image must be able to verify an ML-DSA PKAM signature, because these
#     tests CRAM-onboard an atSign with a post-quantum keypair. The published
#     `atsigncompany/virtualenv:vip` cannot, so the default is the locally
#     built `at_virtual_env:local`.
#
#     ⚠️ A run against `vip` fails with a server-side `AT0010-Exception:
#     RangeError` out of PKAM, which reads as a client bug and is not one.
#
#     To match CI exactly, or to run against a published build on purpose:
#
#         VIRTUALENV_IMAGE=atsigncompany/virtualenv:dev_env ./runLocal.sh
#         VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip     ./runLocal.sh
#
# NOTE: tests that spawn at_activate must pass the root port to the child. It
# builds its own client and defaults to 64, so a base-port run hangs to timeout
# with nothing red.
#
# With no BASE_PORT this suite binds the same ports as tests/at_functional_test
# (64, 25000-25999, 6379), so the two cannot run at the same time. Give them
# different base ports and they can.
#
# CRAM secrets are one-shot: a second run against a virtualenv that already
# onboarded these atSigns fails. The compose down below is what makes a re-run
# work, so do not skip it.

cd "$(dirname "$0")"

if [[ -n "${1:-}" ]]; then
  BASE_PORT="$1"
  export VIRTUALENV_BASE_PORT="$BASE_PORT"
  export VE_ROOT_PORT="$BASE_PORT"
  export VE_REDIS_PORT=$((BASE_PORT + 99))
  export VE_SECONDARY_LOW=$((BASE_PORT + 1))
  export VE_SECONDARY_HIGH=$((BASE_PORT + 98))
  echo "*** Using base port ${BASE_PORT} (range ${BASE_PORT}-$((BASE_PORT + 99)))"
else
  echo "*** Using legacy fixed ports (64 / 25000-25999 / 6379)"
fi

echo "*** Getting dependencies" && dart pub get

export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"
echo "*** Using image ${VIRTUALENV_IMAGE}"

echo "*** docker compose down" && docker compose down
# A locally built image is on no registry, so pulling it fails the run.
if [[ "$VIRTUALENV_IMAGE" == *"/"* ]]; then
  echo "*** docker compose pull" && docker compose pull
else
  echo "*** docker compose pull SKIPPED (local image ${VIRTUALENV_IMAGE})"
fi
echo "*** docker compose up" && docker compose up -d

echo "*** Checking docker readiness" && dart run check_docker_readiness.dart

# NOTE: not check_test_env.dart. It polls `lookup:publickey@sitaram` until it
# answers - state only pkamLoad creates - so in a suite that runs without
# pkamLoad it can never pass: it hangs for its full five-minute timeout and
# then fails, which reads as a broken environment.
echo "*** Waiting 10s for the atSigns to come up" && sleep 10

echo "*** Clearing client test storage"
rm -rf test/hive
find test -name '*.atKeys' -delete 2>/dev/null || true

# at_onboarding_cli falls back to $HOME/.atsign/keys - the real one - whenever
# a preference leaves atKeysFilePath null or an auth_cli invocation omits -k,
# and on a developer machine that directory holds live personal keyfiles. A
# demo-atSign keyfile left there outlives the container the compose down above
# just recycled, and onboarding refuses when a keyfile already exists, so the
# next run fails with "Keys file already exists" for an atSign the fresh
# virtualenv has never onboarded - which reads as a product bug and is not.
# With a throwaway HOME such a keyfile lands beside it and goes when it does,
# and the real ~/.atsign/keys is neither written nor read.
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
# ACCEPTANCE_REPORT opts the run into a machine-readable JSON test stream, for
# the acceptance ledger to join against the catalogue's citations.
REPORT_ARG=""
if [[ -n "${ACCEPTANCE_REPORT:-}" ]]; then
  REPORT_ARG="--file-reporter json:${ACCEPTANCE_REPORT}"
  echo "*** Writing acceptance report to ${ACCEPTANCE_REPORT}"
fi
HOME="$TEST_HOME" PUB_CACHE="${PUB_CACHE:-$REAL_HOME/.pub-cache}" \
  dart test --concurrency=1 -r expanded ${REPORT_ARG}
TEST_EXIT=$?
set -e

echo "*** docker compose down" && docker compose down

exit "$TEST_EXIT"
