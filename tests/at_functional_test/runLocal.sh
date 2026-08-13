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

# Wait for pkamLoad to have actually installed the PKAM public keys.
#
# `supervisorctl start` returns as soon as the program is running, and the
# program sleeps 25 seconds before installing anything — so on its own it
# guarantees nothing. check_test_env below is not this wait either: it proves
# that ONE atSign (@sitaram🛠) has ONE record.
#
# When the suite starts before the keys are in, every authentication fails with
# "privatekey:at_pkam_publickey does not exist in keystore" and it presents as
# dozens of failures in whichever unrelated tests happened to run — sync,
# notify, put — rather than as a setup problem. That misattribution is the
# expensive part: the failing tests are not the broken thing.
#
# @srie and @sachin are deliberately NOT in this list. They are the
# CRAM-onboardable atSigns, and their onboarding tests require them to have no
# PKAM key yet, so pkamLoad leaves them out by design.
echo "*** Waiting for pkamLoad to install PKAM keys"
for attempt in $(seq 1 60); do
  # One exec per poll, listing whatever is still missing. A failed exec yields
  # a non-empty result on purpose, so a container that went away keeps us
  # waiting and then fails loudly rather than reading as "nothing missing".
  if ! missing=$(docker exec test-virtualenv-1 sh -c '
      for a in "@alice🛠" "@bob🛠" "@sitaram🛠" "@eve🛠" "@denise"; do
        grep -q "cramAndPkamAuth successful for $a" /apps/logs/pkam.log \
          2>/dev/null || printf "%s " "$a"
      done'); then
    missing="(could not read /apps/logs/pkam.log)"
  fi

  if [[ -z "${missing// /}" ]]; then
    echo "*** PKAM keys installed"
    break
  fi

  if [[ "$attempt" -eq 60 ]]; then
    echo "!!! pkamLoad has not installed PKAM keys for: $missing"
    echo "!!! Refusing to run the suite: every test authenticating as one of"
    echo "!!! those would fail with 'at_pkam_publickey does not exist in"
    echo "!!! keystore', in tests that have nothing to do with the cause."
    docker exec test-virtualenv-1 tail -20 /apps/logs/pkam.log || true
    exit 1
  fi
  sleep 2
done

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
