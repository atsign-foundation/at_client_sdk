#!/usr/bin/env bash
# Builds the browser entries into build/: at_client.js (dart2js) and
# at_client.wasm + at_client.mjs (dart2wasm) from the dev entry, and
# at_client_web.js and at_client_web.wasm + at_client_web.mjs from the bridge.
# Class names stay unminified so rejected Errors name their Dart type.
# A dart2wasm failure warns and exits 0 unless WASM_REQUIRED=1.
set -euo pipefail

cd "$(dirname "$0")/.."
out=build
mkdir -p "$out"

# Compiles web/$1.dart as build/$2 with both compilers.
build_entry() {
  local entry="web/$1.dart" name=$2
  dart compile js -O2 --no-minify "$entry" -o "$out/$name.js"
  if ! dart compile wasm -O2 --no-minify "$entry" -o "$out/$name.wasm"; then
    if [[ "${WASM_REQUIRED:-0}" == 1 ]]; then
      echo "dart2wasm compile failed for $entry" >&2
      exit 1
    fi
    echo "warning: dart2wasm compile failed for $entry; $name.js is still built" >&2
  fi
}

build_entry at_client_wasm_entry at_client
build_entry at_client_web_entry at_client_web

ls -l "$out"
