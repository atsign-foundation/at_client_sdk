#!/usr/bin/env bash
# Prints every Scenario: title in features/at_client_web that no test in
# packages/at_client_web/test carries verbatim as a quoted title. Dart tests
# split long titles across adjacent string literals ('a ' 'b'), so adjacent
# same-quote literals (closing quote, whitespace/newlines, opening quote of the
# same kind) are joined first; the title must then be an exact, whole quoted
# string (fixed-string match, no other loosening). Prints nothing when every
# scenario has a proving test.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
feat_dir="$(dirname "$0")"
joined="$(mktemp "${TMPDIR:-/tmp}/check_scenarios.XXXXXX")"
trap 'rm -f "$joined"' EXIT
find "$root/packages/at_client_web/test" -name '*.dart' -print0 |
  xargs -0 perl -0777 -pe "s/'\\s+'//g; s/\"\\s+\"//g; \$_ .= \"\\n\"" >"$joined"
grep -h '^  Scenario: ' "$feat_dir"/*.feature | sed 's/^  Scenario: //' |
  while IFS= read -r title; do
    grep -qF -e "'$title'" -e "\"$title\"" "$joined" || echo "missing: $title"
  done
