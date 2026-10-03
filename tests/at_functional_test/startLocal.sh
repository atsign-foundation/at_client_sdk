#!/usr/bin/env bash
set -euo pipefail

# Bring up a fresh virtualenv and leave it running; run no tests. For driving
# individual test files by hand, or probing a live atServer, without paying a
# container recycle per attempt — runLocal.sh recycles on every invocation.
#
#   ./startLocal.sh          # legacy fixed ports (64 / 25000-25999 / 6379) — same as CI
#   ./startLocal.sh 27000    # base port: root 27000, secondaries 27001-27098, redis 27099
#
# The base port works as in runLocal.sh, passed or exported as
# VIRTUALENV_BASE_PORT, and this holds the same lock on the pack until the
# virtualenv is stopped.

cd "$(dirname "$0")"
source ../lib/rig_lock.sh

if [[ -n "${1:-}" ]]; then
  VIRTUALENV_BASE_PORT="$1"
fi
if [[ -n "${VIRTUALENV_BASE_PORT:-}" ]]; then
  if [[ ! "$VIRTUALENV_BASE_PORT" =~ ^[0-9]+$ ]]; then
    echo "*** Not a base port: ${VIRTUALENV_BASE_PORT}" >&2
    exit 2
  fi
  BASE_PORT="$VIRTUALENV_BASE_PORT"
  export VIRTUALENV_BASE_PORT
  export VE_ROOT_PORT="$BASE_PORT"
  export VE_REDIS_PORT=$((BASE_PORT + 99))
  export VE_SECONDARY_LOW=$((BASE_PORT + 1))
  export VE_SECONDARY_HIGH=$((BASE_PORT + 98))
  export COMPOSE_PROJECT_NAME="at_functional_test-${BASE_PORT}"
  echo "*** Using base port ${BASE_PORT} (range ${BASE_PORT}-$((BASE_PORT + 99)))"
else
  echo "*** Using legacy fixed ports (64 / 25000-25999 / 6379)"
fi

lock_pack

echo "*** Getting dependencies" && pub_get_locked

# The virtualenv image, read by docker-compose.yaml. Defaults to the locally
# built PQ-capable image; set VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip (or
# a pinned tag) to run against a registry image instead.
export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"

cd test
echo "*** docker compose down" && docker compose down
# A locally built image is on no registry, so pulling it fails the run.
if [[ "$VIRTUALENV_IMAGE" == *"/"* ]]; then
  echo "*** docker compose pull (${VIRTUALENV_IMAGE})" && docker compose pull
else
  echo "*** docker compose pull SKIPPED (local image ${VIRTUALENV_IMAGE})"
fi
echo "*** docker compose up" && docker compose up -d
cd ..

echo "*** Checking docker readiness" && dart run test/check_docker_readiness.dart

echo "*** Executing pkamLoad" \
  && docker compose -f test/docker-compose.yaml exec -T virtualenv supervisorctl start pkamLoad

echo "*** Checking test environment" && dart run test/check_test_env.dart

echo "*** Clearing client test storage" && rm -rf test/hive && rm -f test/testData/@srie.atKeys

echo -n "*** Container ready - press enter when you want to stop the container"

read

echo "*** docker compose down" && (cd test && docker compose down)

