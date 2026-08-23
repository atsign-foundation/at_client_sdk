#!/usr/bin/env bash
#
# Render the acceptance ledger: every catalogue row, and whether the live test
# it cites actually ran and passed in THIS set of runs.
#
# CI emits the ledger's inputs and uploads them as artefacts, but nothing in
# the tree ever joined them — `packages/at_client/tool/acceptance_ledger.dart`
# was invoked only by the usage comment inside itself, so every ledger so far
# was reassembled by hand. This is that command.
#
# Usage:
#   tools/acceptance_ledger.sh                 # unit sources only, no docker
#   tools/acceptance_ledger.sh --with-live     # also run the live packs (slow)
#   tools/acceptance_ledger.sh --out FILE      # default: acceptance-ledger.md
#
# WHAT THE VERDICTS MEAN, and why the default is not the whole picture.
# A row is PROVEN only when EVERY test it cites ran and passed in a report you
# supplied — worst verdict wins, because a row is not proven just because one
# of its several citations happened to run. So the default run, which supplies
# only the unit sources, reports NOT-EXERCISED for every row citing a live
# pack. That is the tool being accurate about the runs it was given, not a
# coverage regression, and the two numbers are not comparable. Use --with-live
# before quoting a total anywhere.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

OUT="$ROOT/acceptance-ledger.md"
WITH_LIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-live) WITH_LIVE=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

CITATIONS="$ROOT/packages/at_client/citations.jsonl"

# One image for every pack, so a mismatch cannot show up in the ledger as a
# failing row. All three runners now default to `at_virtual_env:local` too, so
# this agrees with them rather than fighting them; setting it here means a
# ledger run cannot be split across images even if a runner's default drifts.
#
# It has to be an image that verifies ML-DSA PKAM: the CLI pack CRAM-onboards
# an atSign with a post-quantum keypair, and against the published
# `atsigncompany/virtualenv:vip` that fails as a server-side `AT0010 RangeError`
# out of PKAM, which reads as a client bug. Override deliberately to measure
# against a published build.
export VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"

# ⚠️ `provenIn` APPENDS to this file. Two runs against the same path silently
# double every citation — the ledger then reports "278 citations" for a
# catalogue of 139, and the verdicts still look right because each duplicate
# resolves the same way. Delete it here rather than trusting the caller.
rm -f "$CITATIONS"

REPORTS=()

# Records the exit code without letting it decide anything: a suite that FAILED
# is exactly when knowing which rows lost their proof matters most, so a red
# run must still produce a ledger.
run_suite() {
  local label="$1"; shift
  echo "*** $label"
  "$@"
  local code=$?
  if [[ $code -ne 0 ]]; then
    echo "*** $label exited $code — continuing, the ledger is about the runs"
  fi
  return 0
}

echo "*** Unit sources"

# One run produces BOTH halves for at_client: the citations (every provenIn
# call, recorded as it runs) and the report saying which of those tests passed.
run_suite "at_client unit suite" env ACCEPTANCE_LEDGER="$CITATIONS" \
  bash -c 'cd "$0/packages/at_client" && dart test --concurrency=1 \
    --file-reporter json:acceptance-report.json' "$ROOT"
REPORTS+=("$ROOT/packages/at_client/acceptance-report.json")

run_suite "at_auth unit suite" \
  bash -c 'cd "$0/packages/at_auth" && dart test --concurrency=1 \
    --file-reporter json:acceptance-report.json' "$ROOT"
REPORTS+=("$ROOT/packages/at_auth/acceptance-report.json")

if [[ $WITH_LIVE -eq 1 ]]; then
  echo "*** Live packs (each recycles its own virtualenv; this takes a while)"
  for pack in at_functional_test at_end2end_test at_onboarding_cli_functional_tests; do
    run_suite "$pack" \
      bash -c 'cd "$0/tests/$1" && ACCEPTANCE_REPORT=acceptance-report.json ./runLocal.sh' \
      "$ROOT" "$pack"
    REPORTS+=("$ROOT/tests/$pack/acceptance-report.json")
  done
else
  echo "*** Live packs SKIPPED (--with-live runs them)."
  echo "*** Rows citing a live pack will read NOT-EXERCISED, which is a"
  echo "*** statement about this run and not about the code."
fi

# An absent report is not an error — a suite may have died before writing one —
# but it must be said out loud, or the ledger silently narrows and reads as a
# coverage result.
ARGS=()
for r in "${REPORTS[@]}"; do
  if [[ -s "$r" ]]; then
    ARGS+=(--report "$r")
  else
    echo "*** MISSING: $r — its rows will read NOT-EXERCISED"
  fi
done

if [[ ! -s "$CITATIONS" ]]; then
  echo "no citations were recorded at $CITATIONS." >&2
  echo "The at_client suite must run for provenIn to record anything." >&2
  exit 1
fi

echo "*** Rendering"
cd "$ROOT/packages/at_client"
dart run tool/acceptance_ledger.dart \
  --citations "$CITATIONS" \
  "${ARGS[@]}" \
  --out "$OUT"
