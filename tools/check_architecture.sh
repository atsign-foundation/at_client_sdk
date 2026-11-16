#!/usr/bin/env bash
# Runs every guard docs/architecture/invariants.md names as a rule's check
# that runs without an atServer: the guard tests in at_client, at_auth,
# at_chops, at_lookup and at_utils, the wasm gates, and the
# released_envelope_reader check. A failure names the rule it holds.
#
# Left to CI: functional_tests_upgrade, which needs the virtualenv. A1's lints
# are reported by `dart analyze`, not run here.
#
# Run from anywhere in the repo. A guard added to the page is added here, so
# that AGENTS.md and the PR template keep naming one command.
set -euo pipefail

root=$(git rev-parse --show-toplevel)

guards() {
  local package=$1
  shift
  (cd "$root/$package" && dart test --concurrency=1 "$@")
}

guards packages/at_client \
  test/architecture \
  test/import_topology_test.dart \
  test/public_api_surface_test.dart \
  test/web_safe_test.dart \
  test/storage \
  test/rollout_axis_pinning_test.dart \
  test/acceptance/architecture_guard_test.dart \
  test/wire_literal_pins_test.dart
guards packages/at_auth \
  test/at_keys_golden_test.dart \
  test/wire_literal_pins_test.dart
guards packages/at_chops test/wire_literal_pins_test.dart
guards packages/at_lookup test/web_safe_test.dart
guards packages/at_utils test/web_safe_test.dart

(cd "$root" && dart run wasm_shakedown --config .github/wasm_gates.yaml)

(
  cd "$root/tests/released_envelope/4.0.0"
  dart pub get --offline --enforce-lockfile > /dev/null 2>&1 ||
    dart pub get --enforce-lockfile
  dart test --concurrency=1
)
