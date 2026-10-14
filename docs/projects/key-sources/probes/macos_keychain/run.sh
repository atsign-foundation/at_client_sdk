#!/usr/bin/env bash
# Replays the macOS keychain arms. Items are created in the login keychain
# under unique service names and deleted at the end.
set -u
cd "$(dirname "$0")"
dart pub get >/dev/null
mkdir -p out
dart compile exe bin/probe.dart -o out/writer >/dev/null
sed "s/const buildTag = 'v1';/const buildTag = 'other';/" bin/probe.dart > bin/probe_other.dart
dart compile exe bin/probe_other.dart -o out/other >/dev/null
SVC="atsign-kc-probe-$$"; ANY="atsign-kc-probe-any-$$"; TOOL="atsign-kc-probe-tool-$$"; STDIN="atsign-kc-probe-stdin-$$"
HEX=$(python3 -c "print(''.join('%02x'%((i*7+3)%251) for i in range(16384)))")

echo '--- negative control: read before the item exists (expect -25300)'
out/writer read "$SVC"
echo '--- writer stores 16384 bytes and reads its own item (expect 0)'
out/writer add "$SVC" 16384; out/writer read "$SVC"
echo '--- a different binary reads it'
out/other read "$SVC"
echo '--- the writer rebuilt at the same path reads it'
sed -i '' "s/const buildTag = 'v1';/const buildTag = 'v2';/" bin/probe.dart
dart compile exe bin/probe.dart -o out/writer >/dev/null
sed -i '' "s/const buildTag = 'v2';/const buildTag = 'v1';/" bin/probe.dart
out/writer read "$SVC"
echo '--- item created allowing any app (-A), read by both binaries'
security add-generic-password -s "$ANY" -a probe -A -X "$HEX"
out/other read "$ANY"; out/writer read "$ANY"
echo '--- security -i over stdin (reports the stored length)'
printf 'add-generic-password -s %s -a probe -X %s\n' "$STDIN" "$HEX" | security -i >/dev/null 2>&1
OUT=$(security find-generic-password -s "$STDIN" -a probe -w 2>/dev/null); echo "stored hex chars=${#OUT} of ${#HEX}"
echo '--- security tool writes and reads 16384 bytes'
security add-generic-password -s "$TOOL" -a probe -X "$HEX"
OUT=$(security find-generic-password -s "$TOOL" -a probe -w); echo "matches=$([ "$OUT" = "$HEX" ] && echo true || echo false)"
echo '--- our binary reads the tool-made item'
out/writer read "$TOOL"

for s in "$SVC" "$ANY" "$TOOL" "$STDIN"; do security delete-generic-password -s "$s" -a probe >/dev/null 2>&1; done
rm -f bin/probe_other.dart
