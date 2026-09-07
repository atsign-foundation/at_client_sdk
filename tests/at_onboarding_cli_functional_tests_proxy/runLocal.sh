#!/usr/bin/env bash
set -euo pipefail

# Run the onboarding-CLI *proxy* functional suite locally, the way CI runs it
# (.github/workflows/at_libraries.yaml, functional_tests_at_onboarding_cli,
# matrix entry at_onboarding_cli_functional_tests_proxy).
#
# This pack existed with no runner for a long time, which made it invisible to
# anyone enumerating the local suites with `find tests -name runLocal.sh` - it
# is the fourth pack, not the third. That is the reason this file exists.
#
# It is a sibling of tests/at_onboarding_cli_functional_tests/runLocal.sh and
# shares its two rules, for the same reasons:
#
#  1. pkamLoad is NOT started. These tests CRAM-onboard, so they need atSigns
#     holding no PKAM key yet. Starting it makes onboarding fail as "already
#     activated", which reads like a product bug and is not.
#  2. check_test_env.dart is NOT run - this pack does not ship one, and the
#     sibling's would hang anyway: it polls for state only pkamLoad creates.
#     CI runs readiness, then a sleep, then the tests.
#
# What differs from the sibling: a second container, at_proxyserver, sits in
# front of the virtualenv and the tests reach the atServer through it
# (--rootServer proxy:vip.ve.atsign.zone:443). So this pack additionally needs
# host port 443 free.
#
# PREREQUISITE, from README.md: the host must resolve vip.ve.atsign.zone to
# 127.0.0.1. The compose file's extra_hosts only covers the containers; the
# test process runs on the host and dials the proxy by that name.
#
#     127.0.0.1       vip.ve.atsign.zone
#
# Ports: 64, 25000-25999, 6379, 9001 and 443. The first three are the same ones
# tests/at_functional_test and tests/at_onboarding_cli_functional_tests bind, so
# none of the three packs can run at the same time as another.
#
# CRAM secrets are one-shot: a second run against a virtualenv that already
# onboarded these atSigns fails. The compose down below is what makes a re-run
# work, so do not skip it.
#
# The tests name their own keyfiles with a per-run uuid and delete them in
# teardown, so unlike the sibling this one needs no throwaway HOME.

cd "$(dirname "$0")"

echo "*** Getting dependencies" && dart pub get

echo "*** docker compose down" && docker compose down
echo "*** docker compose pull" && docker compose pull
echo "*** docker compose up" && docker compose up -d

echo "*** Checking docker readiness" && dart run check_docker_readiness.dart

echo "*** Waiting 10s for the atSigns to come up" && sleep 10

echo "*** Running tests"
# Let the run fail through to cleanup, then propagate its code - otherwise
# set -e aborts before teardown on the very failure this exists to catch.
set +e
dart test --concurrency=1 -r expanded
TEST_EXIT=$?
set -e

echo "*** docker compose down" && docker compose down

exit "$TEST_EXIT"
