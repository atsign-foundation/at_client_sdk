#!/usr/bin/env bash
set -euo pipefail

# Run the onboarding-CLI functional suite locally.
#
#   ./runLocal.sh
#
# Deliberately NOT a copy of tests/at_functional_test/runLocal.sh. Two
# differences matter, and both are documented in this package's README and
# docker-compose.yaml:
#
#  1. pkamLoad is NOT started. That script installs PKAM public keys for the
#     demo atSigns, and these tests CRAM-onboard - they need atSigns that hold
#     no PKAM key yet. Starting it makes onboarding tests fail as "already
#     activated", which reads like a product bug and is not.
#  2. The image defaults to the PUBLISHED virtualenv, matching CI. A local run
#     that needs post-quantum activation opts in, because the published image
#     has lagged ML-DSA PKAM verification throughout this branch:
#
#         VIRTUALENV_IMAGE=at_virtual_env:local ./runLocal.sh
#
# This suite binds the same ports as tests/at_functional_test (64, 443,
# 25000-25999, 6379), so the two cannot run at the same time.
#
# CRAM secrets are one-shot: a second run against a virtualenv that already
# onboarded these atSigns fails. The compose down below is what makes a re-run
# work, so do not skip it.

cd "$(dirname "$0")"

echo "*** Getting dependencies" && dart pub get

export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-atsigncompany/virtualenv:vip}"
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

# NOT check_test_env.dart, and not an oversight. That script polls
# `lookup:publickey@sitaram` until it answers - state that only pkamLoad
# creates - so in a suite that deliberately runs without pkamLoad it can never
# pass. It hangs for its full five-minute timeout and then fails, which reads
# as a broken environment. CI does not call it either (at_libraries.yaml runs
# readiness, then this sleep, then the tests); it is dead code in this package.
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
