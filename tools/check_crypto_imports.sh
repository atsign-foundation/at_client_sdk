#!/usr/bin/env bash
set -euo pipefail

# Enforces at_chops as the single crypto boundary.
#
# Consumer at_ packages must route encryption, signing and KDF through
# at_chops — they must NOT import a crypto primitive library directly. With one
# audited boundary, a primitive can be swapped in one place and post-quantum
# work (X-Wing/MLS) lands in at_chops without touching consumers.
#
# Scope is SECURITY crypto in consumers. A non-security naming hash in a
# foundational leaf (at_utils.getShaForAtSign) is out of scope by design.
#
# Whitelist (out of scope by design):
#   at_chops         - the wrapper; it owns the primitive libraries.
#   at_utils         - foundational leaf below at_chops; its sha256 is a
#                      non-security naming hash and a frozen on-disk identifier.
#   at_login_flutter - being removed by a separate effort.
#   at_client v4-quarantine files - AES reachable only via @Deprecated
#                      stream/file methods, slated for removal in v4.
#
# To move the boundary, edit the whitelist below with a justification.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Forbidden direct crypto-lib imports (anchored on the `package:` prefix so
# prose mentions like "wraps crypton's RSA..." are not matched).
pattern="package:(crypton|crypto/crypto\.dart|encrypt/encrypt\.dart|pointycastle|basic_utils|cryptography)"

# Packages entirely exempt.
exempt_pkgs=" at_chops at_utils at_login_flutter "

# File-level exemptions (paths relative to repo root).
exempt_files=(
  "packages/at_client/lib/src/util/encryption_util.dart"
  "packages/at_client/lib/src/converters/encryption/aes_converter.dart"
)

is_exempt_file() {
  local f="$1"
  for ef in "${exempt_files[@]}"; do
    [[ "$f" == "$ef" ]] && return 0
  done
  return 1
}

violations=0
for dir in packages/*/; do
  pkg="$(basename "$dir")"
  [[ "$exempt_pkgs" == *" $pkg "* ]] && continue
  [[ -d "${dir}lib" ]] || continue
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if is_exempt_file "$file"; then
      continue
    fi
    echo "FORBIDDEN crypto-lib import: $file"
    grep -nE "$pattern" "$file" | sed 's/^/    /'
    violations=$((violations + 1))
  done < <(grep -rlE "$pattern" "${dir}lib" 2>/dev/null || true)
done

if [[ "$violations" -gt 0 ]]; then
  echo ""
  echo "✗ ${violations} file(s) import a crypto primitive library directly."
  echo "  Route encryption/signing/KDF through at_chops, or (if genuinely out"
  echo "  of scope) add a justified entry to the whitelist in"
  echo "  tools/check_crypto_imports.sh."
  exit 1
fi

echo "✓ No forbidden crypto-lib imports in consumer packages."
