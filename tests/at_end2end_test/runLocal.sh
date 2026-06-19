#!/usr/bin/env bash
set -euo pipefail

# Run the end-to-end suite locally against a virtualenv on a configurable base
# port. Pick a base port that does NOT overlap the functional suite's ports so
# both can run at once (functional defaults to the fixed 64/25000-25999 range).
#
#   ./runLocal.sh [BASE_PORT]      # default 26000  -> root 26000, secondaries 26001-26080
#
# Generates atKeys + config/config.yaml (test/local_setup.dart) from at_demo_data
# for the PKAM demo atSigns, then runs the tests. Both are gitignored.

BASE_PORT="${1:-26000}"
export VIRTUALENV_BASE_PORT="$BASE_PORT"
export VE_TOP_PORT=$((BASE_PORT + 99))

cd "$(dirname "$0")"

echo "*** Getting dependencies" && dart pub get

cd test
echo "*** docker compose down" && docker compose down
# Use the published image; comment out and `docker tag` a local build to
# at_virtual_env:local + edit docker-compose.yaml to use a local atServer.
echo "*** docker compose pull" && docker compose pull
echo "*** docker compose up (base port ${BASE_PORT}, range ${BASE_PORT}-${VE_TOP_PORT})"
docker compose up -d
cd ..

echo "*** Starting pkamLoad (waiting for supervisor)"
for i in $(seq 1 30); do
  if docker exec e2e_virtualenv supervisorctl start pkamLoad >/dev/null 2>&1; then
    echo "    pkamLoad started"
    break
  fi
  sleep 2
done

echo "*** Waiting for virtualenv readiness" && dart run test/check_local_env.dart

echo "*** Generating atKeys + config" && dart run test/local_setup.dart

echo "*** Clearing client test storage" && rm -rf test/hive

echo "*** Running e2e tests"
# Let the test run fail through to cleanup (so a flake doesn't leave the
# container up), then propagate its exit code.
set +e
dart test --concurrency=1 -r expanded
TEST_EXIT=$?
set -e

echo "***"
echo "*** docker compose down" && docker compose -f test/docker-compose.yaml down

exit "$TEST_EXIT"
