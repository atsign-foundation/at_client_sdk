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
# SWAPPED, DELIBERATELY, AND UNCOMMITTED. docker-compose.yaml points at a
# locally built `at_virtual_env:local` instead of the published
# `atsigncompany/virtualenv:vip`, and the pull is disabled to match. The
# published image does not store `EnrollParams.metadata`, so the key-package
# and two-enrollment paths cannot be exercised against it at all.
# Revert this file AND test/docker-compose.yaml before opening a PR — the
# functional pack carries the same pair of edits.
echo "*** docker compose pull SKIPPED (local at_virtual_env:local image)"
echo "*** docker compose up (base port ${BASE_PORT}, range ${BASE_PORT}-${VE_TOP_PORT})"
docker compose up -d
cd ..

# Give ONE atSign a zero-hour self-enrollment grace, so the retirement rows can
# watch a capped legacy enrollment actually age out instead of waiting 30 days.
#
# Per-secondary rather than the `apkamSelfEnrollmentGraceHours` env var, which
# every secondary in the container would inherit: at grace 0 a retrofit kills
# its parent within a millisecond, and the B1 clone rows need a parent that
# survives its sibling's retrofit. So the cap tests get their own atSign and
# everything else keeps the 720h default. Each secondary's `config` is a
# symlink to one shared directory — replacing the symlink with a private copy
# is what makes the setting local to this atSign. The env var must stay unset
# for the yaml to be read at all (env beats yaml in AtSecondaryConfig).
#
# BEFORE pkamLoad, deliberately. Restarting a secondary mid-load severs
# whatever key install was in flight against it and nothing retries — the
# atSign would come up without a public key and every test on it would fail
# at authentication, a long way from this line.
CAP_ATSIGN='eve🛠'
CAP_PORT=25010
echo "*** Waiting for supervisor"
for i in $(seq 1 30); do
  docker exec e2e_virtualenv supervisorctl status >/dev/null 2>&1 && break
  sleep 2
done

echo "*** Setting apkamSelfEnrollmentGraceHours=0 for @${CAP_ATSIGN}"
docker exec e2e_virtualenv sh -c "
  set -e
  d='/atsign/secondary/${CAP_ATSIGN}'
  rm -f \"\$d/config\"
  mkdir -p \"\$d/config\"
  cp /atsign/secondary/base/config/config.yaml \"\$d/config/config.yaml\"
  printf '\nenrollment:\n  apkamSelfEnrollmentGraceHours: 0\n' >> \"\$d/config/config.yaml\"
"
docker exec e2e_virtualenv supervisorctl restart "${CAP_PORT}_@${CAP_ATSIGN}"

echo "*** Starting pkamLoad"
for i in $(seq 1 30); do
  if docker exec e2e_virtualenv supervisorctl start pkamLoad >/dev/null 2>&1; then
    echo "    pkamLoad started"
    break
  fi
  sleep 2
done

# The probe covers the reconfigured atSign as well as the first one, so a load
# that missed it fails here rather than inside a test's setUpAll.
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
