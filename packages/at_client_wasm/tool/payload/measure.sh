#!/usr/bin/env bash
# Compiles each payload variant with dart2wasm -O2 and dart2js -O2 and prints
# raw, gzipped, and brotli bytes of the output, plus the sqlite3.wasm binary.
# Run from packages/at_client_wasm.
set -euo pipefail

out="${1:-build/payload}"
sqlite_version=2.9.4
mkdir -p "$out"

size() { wc -c <"$1" | tr -d ' '; }
gz() { gzip -9c "$1" | wc -c | tr -d ' '; }

has_brotli=true
if ! command -v brotli >/dev/null 2>&1; then
  echo "Note: brotli is not installed, skipping Brotli columns."
  has_brotli=false
fi
br() { brotli -9 -c "$1" | wc -c | tr -d ' '; }

if $has_brotli; then
  printf '%-18s %-10s %10s %10s %10s %10s %10s %10s\n' variant target wasm wasm.gz wasm.br mjs mjs.gz mjs.br
else
  printf '%-18s %-10s %12s %12s %12s %12s\n' variant target wasm wasm.gz mjs mjs.gz
fi

for target in dart2wasm dart2js; do
  for v in remote_only indexed_db sqlite3_wasm sqlite3_adapter; do
    if [ "$target" = "dart2wasm" ]; then
      dart compile wasm -O2 -o "$out/$v.wasm" "tool/payload/$v.dart" >/dev/null
      if $has_brotli; then
        printf '%-18s %-10s %10s %10s %10s %10s %10s %10s\n' "$v" "$target" \
          "$(size "$out/$v.wasm")" "$(gz "$out/$v.wasm")" "$(br "$out/$v.wasm")" \
          "$(size "$out/$v.mjs")" "$(gz "$out/$v.mjs")" "$(br "$out/$v.mjs")"
      else
        printf '%-18s %-10s %12s %12s %12s %12s\n' "$v" "$target" \
          "$(size "$out/$v.wasm")" "$(gz "$out/$v.wasm")" \
          "$(size "$out/$v.mjs")" "$(gz "$out/$v.mjs")"
      fi
    else
      dart compile js -O2 -o "$out/$v.js" "tool/payload/$v.dart" >/dev/null
      if $has_brotli; then
        printf '%-18s %-10s %10s %10s %10s %10s %10s %10s\n' "$v" "$target" \
          "$(size "$out/$v.js")" "$(gz "$out/$v.js")" "$(br "$out/$v.js")" \
          "-" "-" "-"
      else
        printf '%-18s %-10s %12s %12s %12s %12s\n' "$v" "$target" \
          "$(size "$out/$v.js")" "$(gz "$out/$v.js")" \
          "-" "-"
      fi
    fi
  done
done

bin="$out/sqlite3.wasm"
[[ -f $bin ]] || curl -fsSL -o "$bin" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$sqlite_version/sqlite3.wasm"
if $has_brotli; then
  printf '%-18s %-10s %10s %10s %10s %10s %10s %10s\n' sqlite3.wasm "binary" \
    "$(size "$bin")" "$(gz "$bin")" "$(br "$bin")" "-" "-" "-"
else
  printf '%-18s %-10s %12s %12s %12s %12s\n' sqlite3.wasm "binary" \
    "$(size "$bin")" "$(gz "$bin")" "-" "-"
fi
