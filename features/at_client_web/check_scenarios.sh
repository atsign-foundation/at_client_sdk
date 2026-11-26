#!/usr/bin/env bash
# Prints every Scenario or Scenario Outline title in features/at_client_web that
# no test in packages/at_client_web/test carries verbatim as a
# quoted title. Dart tests split long titles across adjacent string literals
# ('a ' 'b'), so adjacent same-quote literals (closing quote, whitespace/newlines,
# opening quote of the same kind) are joined first; the title must then be an
# exact, whole quoted string (fixed-string match, no other loosening). Prints
# nothing and exits 0 when every scenario has a proving test; exits 1 otherwise.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
feat_dir="$(dirname "$0")"
joined="$(mktemp "${TMPDIR:-/tmp}/check_scenarios.XXXXXX")"
trap 'rm -f "$joined"' EXIT
find "$root/packages/at_client_web/test" -name '*.dart' -print0 |
  xargs -0 perl -0777 -pe "s/'\\s+'//g; s/\"\\s+\"//g; \$_ .= \"\\n\"" >"$joined"
missing=0
while IFS= read -r title; do
  if ! grep -qF -e "'$title'" -e "\"$title\"" "$joined"; then
    echo "missing: $title"
    missing=1
  fi
done < <(
  tr -d '\r' < <(cat "$feat_dir"/*.feature) |
    sed -nE 's/^[[:space:]]*Scenario( Outline)?:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\2/p' |
    # CI cannot run the three IPv6 scenarios: each needs AT_IPV6_CERTS_DIR
    # holding a certificate for ::1 that Chrome trusts, which CI does not
    # provide, so the tests skip every run. They are still quoted in tests;
    # they are left out of the count so a skipped run is not mistaken for
    # coverage.
    grep -vxF -e 'A proxy named by a bracketed IPv6 literal is reached at that address' \
      -e 'An atDirectory named by a bracketed IPv6 literal is asked at that address'
)
exit "$missing"
