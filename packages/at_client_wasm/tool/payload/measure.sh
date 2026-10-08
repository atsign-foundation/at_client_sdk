#!/usr/bin/env bash
# Compiles each payload variant with dart2wasm -O2 and prints raw and gzipped
# bytes of the .wasm + .mjs, plus the sqlite3.wasm binary the sqlite3 variant
# also downloads. Run from packages/at_client_wasm.
set -euo pipefail

out="${1:-build/payload}"
sqlite_version=2.9.4
mkdir -p "$out"

size() { wc -c <"$1" | tr -d ' '; }
gz() { gzip -9c "$1" | wc -c | tr -d ' '; }

printf '%-14s %12s %12s %12s %12s\n' variant wasm wasm.gz mjs mjs.gz
for v in remote_only indexed_db sqlite3_wasm; do
  dart compile wasm -O2 -o "$out/$v.wasm" "tool/payload/$v.dart" >/dev/null
  printf '%-14s %12s %12s %12s %12s\n' "$v" \
    "$(size "$out/$v.wasm")" "$(gz "$out/$v.wasm")" \
    "$(size "$out/$v.mjs")" "$(gz "$out/$v.mjs")"
done

bin="$out/sqlite3.wasm"
[[ -f $bin ]] || curl -fsSL -o "$bin" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$sqlite_version/sqlite3.wasm"
printf '%-14s %12s %12s\n' sqlite3.wasm "$(size "$bin")" "$(gz "$bin")"
