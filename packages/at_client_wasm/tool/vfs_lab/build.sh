#!/usr/bin/env bash
# Builds the lab site (page + worker script + sqlite3.wasm) into build/vfs_lab.
# Run from packages/at_client_wasm.
set -euo pipefail

out=build/vfs_lab
wasm=build/payload/sqlite3.wasm
mkdir -p "$out" "$(dirname "$wasm")"

[[ -f $wasm ]] || curl -fsSL -o "$wasm" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm"

dart compile js -O2 -o "$out/e2.dart.js" tool/vfs_lab/web/e2.dart >/dev/null
dart compile js -O2 -o "$out/e3.dart.js" tool/vfs_lab/web/e3.dart >/dev/null
dart compile js -O2 -o "$out/e4.dart.js" tool/vfs_lab/web/e4.dart >/dev/null
cp tool/vfs_lab/web/index.html tool/vfs_lab/web/e3.html tool/vfs_lab/web/e4.html "$wasm" "$out/"
echo "built $out"
