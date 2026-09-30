#!/usr/bin/env bash
#
# demo.sh — play the invitation flow in two windows side by side, Alice on
# the left and Bob on the right, and optionally record it.
#
# Usage: demo/demo.sh [--record <file.mp4>]
#
# Starts a fresh EE with ee/up.sh, builds the app with
# integration_test/two_window_demo.dart as its entry point, and runs one
# instance as Alice and one as Bob. Keep both windows in view until it
# finishes: runs have been seen to stall while they were hidden.
#
# --record captures only the rectangle the two windows fill, with ffmpeg, and
# needs Screen Recording permission for the terminal. The paste dialog
# pre-fills from the clipboard, so the clipboard's text is saved, cleared,
# given the invitation link once Alice has made it, and restored at the end.
#
# The build replaces build/macos/Build/Products/Debug/invitations.app, so run
# `flutter build macos --debug` again before running the app by hand.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../ee/lib.sh"

OUT=""
case "${1:-}" in
  "") ;;
  --record) OUT="${2:?--record needs an output file, e.g. demo.mp4}" ;;
  *) die "usage: demo/demo.sh [--record <file.mp4>]" ;;
esac
if [[ -n "$OUT" ]]; then
  command -v ffmpeg >/dev/null || die "ffmpeg is not on PATH"
  [[ "$OUT" == /* ]] || OUT="$PWD/$OUT"
fi

BUNDLE="$APP_DIR/build/macos/Build/Products/Debug/invitations.app"
BINARY="$BUNDLE/Contents/MacOS/invitations"
TMPD="$HOME/Library/Containers/com.atsign.examples.invitations/Data/tmp"
HANDOFF="$TMPD/invitations_demo_handoff.json"
WORK=$(mktemp -d)
CAPTURE=""

cleanup() {
  [[ -z "$CAPTURE" ]] || kill -INT "$CAPTURE" 2>/dev/null || true
  pkill -f "$BINARY" 2>/dev/null || true
  [[ ! -f "$WORK/clipboard" ]] || pbcopy < "$WORK/clipboard"
}
trap cleanup EXIT

say "Layout"
read -r _ _ W H < <(
  osascript -e 'tell application "Finder" to get bounds of window of desktop' |
    tr -d ','
)
WIN_W=$(( (W - 30) / 2 > 828 ? 828 : (W - 30) / 2 ))
WIN_H=$(( (H - 117 > 1000 ? 1000 : H - 117) / 2 * 2 ))
LEFT=15
BOTTOM=40
TOP=$(( H - BOTTOM - WIN_H ))
ok "screen ${W}x${H} points, two windows of ${WIN_W}x${WIN_H}"

if [[ -n "$OUT" ]]; then
  DEVICE=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 |
    sed -n 's/.*\[\([0-9]*\)\] Capture screen 0.*/\1/p')
  [[ -n "$DEVICE" ]] || die "ffmpeg lists no screen to capture"
  PIXELS=$(ffmpeg -hide_banner -f avfoundation -pixel_format uyvy422 \
    -i "$DEVICE:none" -frames:v 1 -f null - 2>&1 |
    grep -o -E '[0-9]{3,}x[0-9]{3,}' | head -1)
  [[ -n "$PIXELS" ]] || die "could not capture the screen; check Screen Recording permission"
  S=$(( ${PIXELS%x*} / W ))
  CROP="crop=$((2 * WIN_W * S)):$((WIN_H * S)):$((LEFT * S)):$((TOP * S))"
  CROP="$CROP,scale=$((2 * WIN_W)):$WIN_H"
  ok "screen $DEVICE, $PIXELS pixels, recording $CROP"
fi

say "Build"
(cd "$APP_DIR" &&
  flutter build macos --debug -t integration_test/two_window_demo.dart) \
  > "$WORK/build.log" 2>&1 ||
  { tail -20 "$WORK/build.log" >&2; die "the build failed"; }
ok "built the two-window demo"

say "Ephemeral Environment"
"$APP_DIR/ee/up.sh" > "$WORK/up.log" 2>&1 ||
  { tail -20 "$WORK/up.log" >&2; die "ee/up.sh failed"; }
ok "fresh EE and issuer"

say "Two windows"
pbpaste > "$WORK/clipboard" 2>/dev/null || true
printf '' | pbcopy
rm -f "$HANDOFF"*
open -n "$BUNDLE" --env DEMO_ROLE=alice \
  --env "DEMO_FRAME=$LEFT,$BOTTOM,$WIN_W,$WIN_H" \
  --stdout "$WORK/alice.log" --stderr "$WORK/alice.log"
# NOTE: one at a time, so that neither window opens on top of the other.
sleep 5
open -n "$BUNDLE" --env DEMO_ROLE=bob \
  --env "DEMO_FRAME=$((LEFT + WIN_W)),$BOTTOM,$WIN_W,$WIN_H" \
  --stdout "$WORK/bob.log" --stderr "$WORK/bob.log"
sleep 6
ok "Alice on the left, Bob on the right"

if [[ -n "$OUT" ]]; then
  ffmpeg -hide_banner -loglevel error -f avfoundation -capture_cursor 0 \
    -framerate 30 -pixel_format uyvy422 -i "$DEVICE:none" -t 600 \
    -vf "$CROP" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
    -y "$WORK/raw.mp4" < /dev/null > "$WORK/capture.log" 2>&1 &
  CAPTURE=$!
  sleep 3
  ok "recording"
fi
echo go > "$HANDOFF.go"

say "Playing"
copied=0
finished=0
for _ in $(seq 1 720); do
  if (( copied == 0 )) && [[ -s "$HANDOFF" ]]; then
    sed -n 's/.*"link":"\([^"]*\)".*/\1/p' "$HANDOFF" | tr -d '\n' | pbcopy
    copied=1
  fi
  if grep -q -E 'Some tests failed|EXCEPTION CAUGHT' \
    "$WORK/alice.log" "$WORK/bob.log" 2>/dev/null; then
    die "the demo failed; its logs are in $WORK"
  fi
  if grep -q 'DEMO alice finished' "$WORK/alice.log" 2>/dev/null &&
    grep -q 'DEMO bob finished' "$WORK/bob.log" 2>/dev/null; then
    finished=1
    break
  fi
  sleep 0.5
done
(( finished == 1 )) || die "the demo did not finish in 6 minutes; logs in $WORK"
ok "both finished"

if [[ -n "$OUT" ]]; then
  kill -INT "$CAPTURE"
  wait "$CAPTURE" || true
  CAPTURE=""
  # NOTE: the last moments can show the test binding's "Test finished." screen.
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 \
    "$WORK/raw.mp4")
  END=$(awk -v d="$DURATION" 'BEGIN { printf "%.2f", d - 1 }')
  ffmpeg -hide_banner -loglevel error -i "$WORK/raw.mp4" -t "$END" \
    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart \
    -an -y "$OUT"
  ok "recorded $OUT (${END}s)"
fi

cat <<EOF

  Done. The EE is still up: ee/down.sh stops it. Rebuild with
  flutter build macos --debug before running the app by hand.
EOF
