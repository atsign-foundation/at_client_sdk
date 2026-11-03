#!/usr/bin/env bash
# Builds the dev harness into build/: at_client.js (dart2js) and
# at_client.wasm + at_client.mjs (dart2wasm), plus index.html.
# Class names stay unminified so rejected Errors name their Dart type.
# A dart2wasm failure warns and exits 0 unless WASM_REQUIRED=1.
set -euo pipefail

cd "$(dirname "$0")/.."
out=build
entry=web/at_client_js.dart
mkdir -p "$out"

dart compile js -O2 --no-minify "$entry" -o "$out/at_client.js"
cp web/index.html "$out/"

if ! dart compile wasm -O2 --no-minify "$entry" -o "$out/at_client.wasm"; then
  if [[ "${WASM_REQUIRED:-0}" == 1 ]]; then
    echo "dart2wasm compile failed" >&2
    exit 1
  fi
  echo "warning: dart2wasm compile failed; at_client.js is still built" >&2
fi

ls -l "$out"
