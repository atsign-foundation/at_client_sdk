#!/usr/bin/env bash
# Builds the browser entries into build/: at_client.js (dart2js) and
# at_client.wasm + at_client.mjs (dart2wasm) from the compile target, and
# at_client_web.js and at_client_web.wasm + at_client_web.mjs from the bridge.
# Class names stay unminified so rejected Errors name their Dart type.
# A dart2wasm failure warns and exits 0 unless WASM_REQUIRED=1.
# With the argument at_client_bridge_entry it builds only build/at_client_web.js
# (dart2js, no dart2wasm); any other argument is refused.
set -euo pipefail

cd "$(dirname "$0")/.."
out=build

# Compiles web/$1.dart as build/$2 with dart2js and, when $3 is wasm, dart2wasm.
build_entry() {
  local entry="web/$1.dart" name=$2 targets=${3:-wasm}
  dart compile js -O2 --no-minify "$entry" -o "$out/$name.js"
  [[ "$targets" == wasm ]] || return 0
  if ! dart compile wasm -O2 --no-minify "$entry" -o "$out/$name.wasm"; then
    if [[ "${WASM_REQUIRED:-0}" == 1 ]]; then
      echo "dart2wasm compile failed for $entry" >&2
      exit 1
    fi
    echo "warning: dart2wasm compile failed for $entry; $name.js is still built" >&2
  fi
}

mkdir -p "$out"

case "${1:-}" in
  "")
    build_entry at_client_web_entry at_client
    build_entry at_client_bridge_entry at_client_web
    ;;
  at_client_bridge_entry)
    build_entry at_client_bridge_entry at_client_web js
    ;;
  *)
    echo "unknown entry '$1'; expected no argument or at_client_bridge_entry" >&2
    exit 1
    ;;
esac

ls -l "$out"
