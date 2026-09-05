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

echo "*** Running tests"
# Let the run fail through to cleanup, then propagate its code - otherwise
# set -e aborts before teardown on the very failure this exists to catch.
set +e
dart test --concurrency=1 -r expanded
TEST_EXIT=$?
set -e

echo "*** docker compose down" && docker compose down

exit "$TEST_EXIT"
