#!/usr/bin/env bash
set -euo pipefail

# Run the end-to-end suite locally against a virtualenv on a configurable base
# port. Pick a base port that does NOT overlap the functional suite's ports so
# both can run at once (functional defaults to the fixed 64/25000-25999 range).
#
#   ./runLocal.sh [BASE_PORT] [TEST_PATHS...]
#
#   ./runLocal.sh                      # both sets: test/ and test/pq/
#   ./runLocal.sh 26000 test/pq        # post-quantum only
#   ./runLocal.sh 26000 test -x pq     # everything except post-quantum
#
# The default path argument is `test`, which recurses into test/pq/ — so a bare
# run covers both sets. CI does NOT do that: `dart_test.yaml` allowlists the
# files a bare `dart test` may run, and the post-quantum ones are deliberately
# not on it, because the CI e2e jobs point at the long-lived @ce2e atSigns.
# Anything passed here overrides that allowlist.
#
# Generates atKeys + config/config.yaml (test/local_setup.dart) from at_demo_data
# for the PKAM demo atSigns, then runs the tests. Both are gitignored.

BASE_PORT="${1:-26000}"
shift || true
# `A && B` as a bare statement under `set -e` exits the script whenever A is
# false, so the default goes in an if.
if [[ $# -eq 0 ]]; then
  TEST_PATHS=("test")
else
  TEST_PATHS=("$@")
fi

export VIRTUALENV_BASE_PORT="$BASE_PORT"
export VE_TOP_PORT=$((BASE_PORT + 99))

# The virtualenv image. docker-compose.yaml defaults to the published
# `atsigncompany/virtualenv:vip` so CI needs no environment; a local run wants
# a build the registry does not have yet, so default the opposite way here and
# let the caller override:
#
#   VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip ./runLocal.sh
#
# The published image has lagged the PQ work for the whole of this branch — as
# of 2026-08-08 its atServer cannot verify an ML-DSA PKAM signature, and the
# symptom is a server-side `AT0010-Exception: RangeError (length): Invalid
# value: Not in inclusive range 0..47: 48` out of pkamAuthenticate.
export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"

cd "$(dirname "$0")"

echo "*** Getting dependencies" && dart pub get

cd test
echo "*** docker compose down" && docker compose down
# A locally built image is on no registry, so pulling it fails the run. Only
# pull what could actually have come from one.
if [[ "$VIRTUALENV_IMAGE" == *"/"* ]]; then
  echo "*** docker compose pull (${VIRTUALENV_IMAGE})" && docker compose pull
else
  echo "*** docker compose pull SKIPPED (local image ${VIRTUALENV_IMAGE})"
fi
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

echo "*** Running e2e tests (${TEST_PATHS[*]})"
# Let the test run fail through to cleanup (so a flake doesn't leave the
# container up), then propagate its exit code.
set +e
dart test --concurrency=1 -r expanded "${TEST_PATHS[@]}"
TEST_EXIT=$?
set -e

echo "***"
echo "*** docker compose down" && docker compose -f test/docker-compose.yaml down

exit "$TEST_EXIT"
