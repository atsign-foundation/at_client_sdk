#!/usr/bin/env bash
# Prints every Scenario: title in features/at_client_web that no test in
# packages/at_client_web or packages/at_client_wasm/test carries verbatim as
# a quoted title. Prints nothing when every scenario has a proving test.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
dirs=("$root/packages/at_client_web/test" "$root/packages/at_client_web/e2e" "$root/packages/at_client_wasm/test")
grep -h '^  Scenario: ' "$(dirname "$0")"/*.feature | sed 's/^  Scenario: //' |
  while IFS= read -r title; do
    grep -rqF --include='*.ts' --include='*.dart' \
      -e "'$title'" -e "\"$title\"" -e "\`$title\`" "${dirs[@]}" || echo "missing: $title"
  done
