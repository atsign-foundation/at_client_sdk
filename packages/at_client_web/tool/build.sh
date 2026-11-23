#!/usr/bin/env bash
# Builds the browser entries into build/: at_client.js (dart2js) and
# at_client.wasm + at_client.mjs (dart2wasm) from the compile target, and
# at_client_web.js and at_client_web.wasm + at_client_web.mjs from the bridge.
# Class names stay unminified so rejected Errors name their Dart type.
#
# Arguments:
#   (none)                 both entries, dart2js plus a best-effort dart2wasm
#                          (today's behaviour: a wasm failure warns and exits 0
#                          unless WASM_REQUIRED=1)
#   at_client_bridge_entry the bridge only, dart2js
#   --target dart2js       that compile target only, for both entries unless
#   --target dart2wasm     the bridge entry is named as well; --target dart2wasm
#                          forces WASM_REQUIRED=1, so its compile failure exits 1
# Both --target VALUE and --target=VALUE are accepted. --target both and
# --target= (empty) are refused, and so is any unknown target or entry: those
# exit 1 naming the allowed values (dart2js and dart2wasm, or the bridge entry).
set -euo pipefail

cd "$(dirname "$0")/.."
out=build

entry=
target=
target_set=0
no_arguments=0
(( $# > 0 )) || no_arguments=1

refuse() {
  echo "$1" >&2
  echo "allowed: entry at_client_bridge_entry; target dart2js or dart2wasm" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --target)
      (( $# >= 2 )) || refuse "--target needs a value; expected dart2js or dart2wasm"
      target=$2
      target_set=1
      shift 2
      ;;
    --target=*)
      target=${1#--target=}
      target_set=1
      shift
      ;;
    at_client_bridge_entry)
      [[ -z "$entry" ]] || refuse "at_client_bridge_entry given twice"
      entry=$1
      shift
      ;;
    -*)
      refuse "unknown option '$1'; expected --target dart2js or dart2wasm"
      ;;
    *)
      refuse "unknown entry '$1'; expected at_client_bridge_entry, with --target dart2js or dart2wasm"
      ;;
  esac
done

if (( target_set )); then
  case "$target" in
    dart2js | dart2wasm) ;;
    *) refuse "unknown target '$target'; expected dart2js or dart2wasm" ;;
  esac
elif (( no_arguments )); then
  target=both
else
  target=dart2js
fi

if [[ "$target" == dart2wasm ]]; then
  export WASM_REQUIRED=1
fi

# build_entry takes the compiler-level target name.
case "$target" in
  dart2js) targets=js ;;
  dart2wasm) targets=wasm ;;
  *) targets=both ;;
esac

# Compiles web/$1.dart as build/$2 for the requested target(s): js, wasm, or
# both. Stale .js, .wasm and .mjs files for the entry are removed first, so a
# build never leaves two targets' artifacts of the same entry behind.
build_entry() {
  local entry="web/$1.dart" name=$2 targets=${3:-both}
  rm -f "$out/$name.js" "$out/$name.wasm" "$out/$name.mjs"
  if [[ "$targets" != wasm ]]; then
    dart compile js -O2 --no-minify "$entry" -o "$out/$name.js"
  fi
  [[ "$targets" != js ]] || return 0
  if ! dart compile wasm -O2 --no-minify "$entry" -o "$out/$name.wasm"; then
    if [[ "${WASM_REQUIRED:-0}" == 1 ]]; then
      echo "dart2wasm compile failed for $entry" >&2
      exit 1
    fi
    echo "warning: dart2wasm compile failed for $entry; keeping $name.js" >&2
  fi
}

mkdir -p "$out"

if [[ -z "$entry" ]]; then
  build_entry at_client_web_entry at_client "$targets"
  build_entry at_client_bridge_entry at_client_web "$targets"
else
  build_entry at_client_bridge_entry at_client_web "$targets"
fi

ls -l "$out"
