set -u
apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libsecret-tools gnome-keyring dbus-x11 python3 >/dev/null 2>&1; echo "install=$?"
echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-<unset>}"
HEX=$(python3 -c "print(''.join('%02x'%((i*7+3)%251) for i in range(16384)))")
echo '--- L1: store with no session bus (the headless/daemon case)'
printf '%s' "$HEX" | timeout 20 secret-tool store --label=probe service atsign-probe account probe 2>&1 | head -3; echo "L1 rc=${PIPESTATUS[1]}"
echo '--- L2: private session bus + keyring unlocked with a supplied password'
dbus-run-session -- sh -c '
  printf "%s" "probe-keyring-password" | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1
  printf "%s" "$0" | timeout 20 secret-tool store --label=probe service atsign-probe account probe; echo "store rc=$?"
  OUT=$(timeout 20 secret-tool lookup service atsign-probe account probe); echo "lookup rc=$? hexlen=${#OUT} matches=$([ "$OUT" = "$0" ] && echo true || echo false)"
' "$HEX" 2>&1 | grep -v -i 'discover\|warning' | head -6
echo '--- L3: a second session (as after a reboot or restart) looks it up'
dbus-run-session -- sh -c '
  printf "%s" "probe-keyring-password" | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1
  OUT=$(timeout 20 secret-tool lookup service atsign-probe account probe); echo "lookup rc=$? hexlen=${#OUT}"
' 2>&1 | head -3
echo "keyring files: $(ls ~/.local/share/keyrings 2>&1)"
