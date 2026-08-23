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
#  2. The image must be able to verify an ML-DSA PKAM signature, because these
#     tests CRAM-onboard an atSign with a post-quantum keypair. The published
#     `atsigncompany/virtualenv:vip` cannot, so the default is the locally
#     built `at_virtual_env:local` — the same default the other two live
#     runners carry, which is what lets one image serve all three.
#
#     ⚠️ This defaulted to the published `vip` until 2026-08-23, and the note
#     here said so: "A bare run here therefore reproduces that failure rather
#     than CI. Opt in to match CI." A default whose documented behaviour is
#     that a plain `./runLocal.sh` fails is not a default — it is a trap with
#     a footnote, and the footnote is in the one file somebody running the
#     suite has no reason to open. The failure it produced is a server-side
#     `AT0010-Exception: RangeError` out of PKAM, which reads as a client bug
#     and is not one.
#
#     To match CI exactly, or to measure against a published build on purpose:
#
#         VIRTUALENV_IMAGE=atsigncompany/virtualenv:dev_env ./runLocal.sh
#         VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip     ./runLocal.sh
#
# This suite binds the same ports as tests/at_functional_test (64, 443,
# 25000-25999, 6379), so the two cannot run at the same time.
#
# CRAM secrets are one-shot: a second run against a virtualenv that already
# onboarded these atSigns fails. The compose down below is what makes a re-run
# work, so do not skip it.

cd "$(dirname "$0")"

echo "*** Getting dependencies" && dart pub get

export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"
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
# Opt-in machine-readable report for the acceptance ledger. Unset, the run is
# byte-for-byte what it always was; set, the runner ALSO writes a JSON stream
# that `packages/at_client/tool/acceptance_ledger.dart` joins against the
# catalogue's citations to say which rows a run actually exercised.
REPORT_ARG=""
if [[ -n "${ACCEPTANCE_REPORT:-}" ]]; then
  REPORT_ARG="--file-reporter json:${ACCEPTANCE_REPORT}"
  echo "*** Writing acceptance report to ${ACCEPTANCE_REPORT}"
fi
dart test --concurrency=1 -r expanded ${REPORT_ARG}
TEST_EXIT=$?
set -e

echo "*** docker compose down" && docker compose down

exit "$TEST_EXIT"
