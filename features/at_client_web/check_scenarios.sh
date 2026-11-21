#!/usr/bin/env bash
# Prints every Scenario or Scenario Outline title in features/at_client_web that
# no test in packages/at_client_wasm/test/{js,collections} carries verbatim as a
# quoted title. Exits 1 when any scenario is missing.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
dirs=(
  "$root/packages/at_client_wasm/test/js"
  "$root/packages/at_client_wasm/test/collections"
)
missing=0
while IFS= read -r title; do
  if ! grep -rqF --include='*.dart' \
    -e "'$title'" -e "\"$title\"" "${dirs[@]}"; then
    echo "missing: $title"
    missing=1
  fi
done < <(
  tr -d '\r' < <(cat "$(dirname "$0")"/*.feature) |
    sed -nE 's/^[[:space:]]*Scenario( Outline)?:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\2/p'
)
exit "$missing"
