#!/usr/bin/env bash
# Replays the macOS keychain arms with code-signed binaries. Needs a
# code-signing identity, named in SIGNING_IDENTITY, for example
#   SIGNING_IDENTITY="Apple Development: Your Name (ABCDE12345)" ./run_signed.sh
# List yours with: security find-identity -v -p codesigning
# Items are created under unique service names and deleted at the end, and the
# signed binaries are removed.
set -u
cd "$(dirname "$0")"
: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY to a code-signing identity}"
dart pub get >/dev/null
mkdir -p out
build() { # $1 = output name, $2 = build tag
  sed "s/const buildTag = 'v1';/const buildTag = '$2';/" bin/probe.dart > "bin/probe_$1.dart"
  dart compile exe "bin/probe_$1.dart" -o "out/$1" >/dev/null
}
sign() { # $1 = output name
  codesign --force -s "$SIGNING_IDENTITY" --options=runtime \
    --entitlements entitlements.plist --identifier "com.atsign.kcprobe.$1" \
    --timestamp=none "out/$1" >/dev/null
}
build writer w1; sign writer
build other o1; sign other
build unsigned u1
for b in writer other unsigned; do
  echo "$b: $(codesign -dv "out/$b" 2>&1 | grep -E '^(Identifier|TeamIdentifier)=' | tr '\n' ' ')"
done
DEF="atsign-kc-probe-sdef-$$"; ANY="atsign-kc-probe-sany-$$"

echo '--- negative control: read before the item exists (expect -25300)'
out/writer read "$DEF"
echo '--- signed writer: default access list, store and read its own item'
out/writer add "$DEF" 16384; out/writer read "$DEF"
echo '--- a second signed binary, same team, reads the default item'
out/other read "$DEF"
echo '--- signed writer: all-applications access list'
out/writer addany "$ANY" 16384
echo '--- the second signed binary reads the all-applications item'
out/other read "$ANY"
echo '--- an unsigned binary reads the all-applications item'
out/unsigned read "$ANY"
echo '--- the writer, rebuilt with a new code hash and re-signed, reads its default item'
build writer w2-upgraded; sign writer
out/writer read "$DEF"

out/writer delete "$DEF"; out/writer delete "$ANY"
rm -rf out bin/probe_writer.dart bin/probe_other.dart bin/probe_unsigned.dart
