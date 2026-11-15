#!/usr/bin/env bash
# Runs every architecture guard named in docs/architecture/invariants.md that
# a change to at_client can trip: the tests under test/architecture/, the other
# at_client guard tests, and the wasm gates. A failure names the rule it holds.
#
# Run from anywhere in the repo. A guard added later is added here, so that
# AGENTS.md and the PR template keep naming one command.
set -euo pipefail

root=$(git rev-parse --show-toplevel)

(
  cd "$root/packages/at_client"
  dart test \
    test/architecture \
    test/import_topology_test.dart \
    test/public_api_surface_test.dart \
    test/storage/import_boundary_test.dart \
    test/acceptance/architecture_guard_test.dart \
    test/wire_literal_pins_test.dart
)

cd "$root"
dart run wasm_shakedown --config .github/wasm_gates.yaml
