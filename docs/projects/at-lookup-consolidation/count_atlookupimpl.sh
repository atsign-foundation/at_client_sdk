#!/usr/bin/env bash
# The acceptance gate for the at_lookup consolidation: ZERO uses of
# AtLookupImpl in LIB CODE and READMEs (gkc, 2026-08-19).
#
# Scope is deliberate, not convenience. Tests, examples, docs/ and CHANGELOGs
# keep their references: a CHANGELOG entry describing what AtLookupImpl did in
# a released version is a TRUE statement about that version, and rewriting it
# would falsify the release history rather than clean anything up.
#
# Counting traps this avoids, each of which has produced a wrong number here:
#
#  - `AtLookupImpl` matches as a SUBSTRING inside `MockAtLookupImpl`, so an
#    unanchored pattern over-counts. Both sides are anchored.
#  - `git grep -E` silently ignores \b, so this uses -P (PCRE).
#  - The count must be proven with a POSITIVE control, or a broken pattern and
#    a true zero print the same nothing.
#
# Run from anywhere; resolves the repo root itself.
set -uo pipefail
ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$ROOT" || exit 2

# Not preceded or followed by an identifier character, so MockAtLookupImpl,
# AtLookupImplFoo and the like do not match.
PAT='(?<![A-Za-z0-9_])AtLookupImpl(?![A-Za-z0-9_])'

echo "=== POSITIVE CONTROL: the pattern must find a symbol we know exists ==="
CTRL=$(git grep -cP '(?<![A-Za-z0-9_])AtLookUp(?![A-Za-z0-9_])' -- '*.dart' \
       | awk -F: '{s+=$NF} END {print s+0}')
echo "  AtLookUp (the interface, which survives): $CTRL"
if [ "$CTRL" -eq 0 ]; then
  echo "  ⛔ CONTROL FAILED - the matcher is broken, so any zero below is meaningless"
  exit 2
fi
git grep -P '(?<![A-Za-z0-9_])AtLookUp(?![A-Za-z0-9_])' -- '*.dart' | head -1 | sed 's/^/  matched: /'
echo

# The gated scope: production Dart, and READMEs.
SCOPE=('*/lib/*.dart' '*README.md')

echo "=== AtLookupImpl uses IN SCOPE (lib Dart + READMEs), by file ==="
git grep -cP "$PAT" -- "${SCOPE[@]}" | sort -t: -k2 -rn
TOTAL=$(git grep -cP "$PAT" -- "${SCOPE[@]}" | awk -F: '{s+=$NF} END {print s+0}')
FILES=$(git grep -lP "$PAT" -- "${SCOPE[@]}" | wc -l | tr -d ' ')

# Reported, never gated. Shown so a zero above is not mistaken for a zero
# everywhere - which is the misreading this line exists to prevent.
OUT=$(git grep -cP "$PAT" | awk -F: '{s+=$NF} END {print s+0}')
echo
echo "  (out of scope, NOT gated: $((OUT - TOTAL)) more in tests, examples, docs and CHANGELOGs)"
echo
echo "TOTAL: $TOTAL uses across $FILES files"
echo
if [ "$TOTAL" -eq 0 ]; then
  echo "✅ GATE MET: zero uses of AtLookupImpl in lib code or READMEs."
  exit 0
fi
echo "❌ GATE NOT MET: $TOTAL uses remain."
exit 1
