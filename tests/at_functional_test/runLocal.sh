#!/usr/bin/env bash
set -euo pipefail

# Run the functional suite locally.
#
#   ./runLocal.sh            # legacy fixed ports (64 / 25000-25999 / 6379) — same as CI
#   ./runLocal.sh 27000      # base port: root 27000, secondaries 27001-27080, redis 27099
#
# Pass a BASE_PORT to shift the virtualenv into a [BASE, BASE+99] range so it
# can run alongside another virtualenv (e.g. the e2e suite via its own
# runLocal.sh) on a different base port. The docker-compose.yaml reads the VE_*
# vars exported here; with none set it uses the legacy fixed ports.

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

# The virtualenv image. Defaults to the locally built PQ-capable build (the
# published vip lags the PQ work); override with
# VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip (or a pinned tag) to run against
# a registry image. docker-compose.yaml reads this var.
export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"

cd test
echo "*** docker compose down" && docker compose down
# A locally built image is on no registry, so pulling it fails the run. Only
# pull what could actually have come from one.
if [[ "$VIRTUALENV_IMAGE" == *"/"* ]]; then
  echo "*** docker compose pull (${VIRTUALENV_IMAGE})" && docker compose pull
else
  echo "*** docker compose pull SKIPPED (local image ${VIRTUALENV_IMAGE})"
fi
echo "*** docker compose up" && docker compose up -d
cd ..

echo "*** Checking docker readiness" && dart run test/check_docker_readiness.dart

echo "*** Executing pkamLoad" && docker exec test-virtualenv-1 supervisorctl start pkamLoad

echo "*** Checking test environment" && dart run test/check_test_env.dart

echo "*** Clearing client test storage" && rm -rf test/hive && rm -f test/testData/@srie.atKeys

echo "*** Running tests"
# Let the test run fail through to cleanup (so a flake doesn't leave the
# container up), then propagate its exit code.
set +e
dart test --concurrency=1 -r expanded
TEST_EXIT=$?
set -e

# This can block. The virtualenv container has been seen refusing to stop
# ("Error while Stopping"), and compose then waits on it indefinitely — so a
# run invoked under an outer wall-clock bound is killed HERE, after the tests
# have already finished and reported. The exit code you get back is then the
# timeout's, not the suite's.
#
# So when a bounded run returns non-zero, read the test output before
# concluding anything failed: the suite prints its own "All tests passed!"
# line before this point. Clear a stuck container with
# `docker rm -f test-virtualenv-1`.
echo "*** docker compose down" && (cd test && docker compose down)

exit "$TEST_EXIT"
