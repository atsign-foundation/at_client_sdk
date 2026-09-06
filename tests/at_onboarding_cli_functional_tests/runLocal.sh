#!/usr/bin/env bash
set -euo pipefail

# Run the onboarding-CLI functional suite locally, the way CI runs it
# (.github/workflows/at_libraries.yaml, functional_tests_at_onboarding_cli).
#
# Deliberately NOT a copy of tests/at_functional_test/runLocal.sh. Two
# differences matter, and both cost time when rediscovered:
#
#  1. pkamLoad is NOT started. That script installs PKAM public keys for the
#     demo atSigns, and these tests CRAM-onboard - they need atSigns holding
#     no PKAM key yet. Starting it makes onboarding fail as "already
#     activated", which reads like a product bug and is not.
#  2. check_test_env.dart is NOT run. It polls `lookup:publickey@sitaram`
#     until it answers - state only pkamLoad creates - so in a suite that runs
#     without pkamLoad it can never pass: it hangs for its full timeout and
#     then fails, which reads as a broken environment. CI does not call it
#     either; it runs readiness, then a sleep, then the tests.
#
# This suite binds the same ports as tests/at_functional_test (64,
# 25000-25999, 6379), so the two cannot run at the same time.
#
# CRAM secrets are one-shot: a second run against a virtualenv that already
# onboarded these atSigns fails. The compose down below is what makes a re-run
# work, so do not skip it.

cd "$(dirname "$0")"

echo "*** Getting dependencies" && dart pub get

echo "*** docker compose down" && docker compose down
echo "*** docker compose pull" && docker compose pull
echo "*** docker compose up" && docker compose up -d

echo "*** Checking docker readiness" && dart run check_docker_readiness.dart

echo "*** Waiting 10s for the atSigns to come up" && sleep 10

echo "*** Clearing client test storage"
rm -rf test/hive
find test -name '*.atKeys' -delete 2>/dev/null || true

# These tests onboard through at_onboarding_cli, which writes its keyfiles to
# $HOME/.atsign/keys - the real one. Those keys are for virtualenv-only demo
# atSigns; they outlive the container the compose down above just recycled, and
# `onboard` refuses when a keyfile already exists. So the next local run fails
# with "Keys file already exists" for atSigns the fresh virtualenv has never
# onboarded, which reads as a product bug and is not. Give the run a throwaway
# HOME instead: the keys land beside it and go when it does, and the real
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

echo "*** docker compose down" && docker compose down

exit "$TEST_EXIT"
