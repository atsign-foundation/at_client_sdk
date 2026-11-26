#!/usr/bin/env bash
# Builds the browser entries into build/: at_client.js and at_client_web.js
# (dart2js), or each entry's .wasm module and .mjs loader (dart2wasm), for the
# chosen compile target. Class names stay unminified so rejected Errors name
# their Dart type.
#
# Arguments:
#   (none)                 both entries, dart2js (the default target)
#   at_client_bridge_entry the bridge only, dart2js
#   --target dart2js       both entries, or the named entry, as dart2js
#   --target dart2wasm     both entries, or the named entry, as dart2wasm: the
#                          module and its loader; dart2wasm is a strict target,
#                          so a wasm compile failure exits 1
# Both --target VALUE and --target=VALUE are accepted, at most once: a second
# --target is refused naming both values. --target both and --target= (empty)
# are refused, and so is any unknown target or entry: those exit 1 naming the
# allowed values (dart2js and dart2wasm, or the bridge entry).
# Every build also writes build/bridge-manifest.json before compiling, generated
# from Dart constants and byte-identical for both compile targets.
set -euo pipefail

cd "$(dirname "$0")/.."
out=build

entry=
target=
target_set=0

refuse() {
  echo "$1" >&2
  echo "allowed: entry at_client_bridge_entry; target dart2js or dart2wasm" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --target)
      (( $# >= 2 )) || refuse "--target needs a value; expected dart2js or dart2wasm"
      value=$2
      shift 2
      ;;
    --target=*)
      value=${1#--target=}
      shift
      ;;
    at_client_bridge_entry)
      [[ -z "$entry" ]] || refuse "at_client_bridge_entry given twice"
      entry=$1
      shift
      continue
      ;;
    -*) refuse "unknown option '$1'; expected --target dart2js or dart2wasm" ;;
    *) refuse "unknown entry '$1'; expected at_client_bridge_entry, with --target dart2js or dart2wasm" ;;
  esac
  (( ! target_set )) || refuse "--target given twice: '$target' then '$value'"
  target=$value
  target_set=1
done

if (( ! target_set )); then target=dart2js; fi

case "$target" in
  dart2js|dart2wasm) ;;
  *) refuse "unknown target '$target'; expected dart2js or dart2wasm" ;;
esac

# Compiles web/$1.dart as build/$2 for the requested compile target.
# Stale .js, .wasm and .mjs files for the entry, and the .js.deps, .js.map and
# .js.sha256 sidecars a dart2js compile leaves, are removed first, so a build
# never leaves two targets' artifacts of the same entry behind.
build_entry() {
  local entry="web/$1.dart" name=$2 target=$3
  rm -f "$out/$name.js" "$out/$name.wasm" "$out/$name.mjs" \
    "$out/$name.js.deps" "$out/$name.js.map" "$out/$name.js.sha256"
  case "$target" in
    dart2js)
      dart compile js -O2 --no-minify "$entry" -o "$out/$name.js"
      ;;
    dart2wasm)
      if ! dart compile wasm -O2 --no-minify "$entry" -o "$out/$name.wasm"; then
        echo "dart2wasm compile failed for $entry" >&2
        exit 1
      fi
      ;;
  esac
}

mkdir -p "$out"

# Published with every build. The generator's self-check exits 1 on a const
# that is empty, unsorted, duplicated or overlapping, so `set -e` fails the
# build before either entry is compiled.
dart tool/manifest.dart --out "$out/bridge-manifest.json"

if [[ -z "$entry" ]]; then
  build_entry at_client_web_entry at_client "$target"
  build_entry at_client_bridge_entry at_client_web "$target"
else
  build_entry at_client_bridge_entry at_client_web "$target"
fi

ls -l "$out"
