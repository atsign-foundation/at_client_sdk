set -u
W=$(mktemp -d /tmp/kcprobe.XXXXXX); U=kcprobe-$(date +%s)
python3 -c "import sys;sys.stdout.buffer.write(bytes((i*7+3)%251 for i in range(16384)))" > $W/secret.bin
cat > $W/svc.sh <<'SVC'
D="$CREDENTIALS_DIRECTORY"; echo "CREDENTIALS_DIRECTORY=$D uid=$(id -u)"
echo "fs=$(stat -f -c %T "$D") dir=$(stat -c '%a %U' "$D") file=$(stat -c '%a %U %s' "$D/atkeys")"
echo "content_ok=$(python3 -c "d=open('$D/atkeys','rb').read();print(len(d)==16384 and d==bytes((i*7+3)%251 for i in range(len(d))))")"
echo "inline=$(cat "$D/inline")"
grep " $D " /proc/self/mountinfo | awk '{print "mount_opts=" $6}'
echo x >> "$D/atkeys" 2>/dev/null; echo "append rc=$?"
cp "$D/atkeys" /tmp/x 2>/dev/null; mv /tmp/x "$D/atkeys" 2>/dev/null; echo "replace rc=$?"
touch "$D/atkeys.bak" 2>/dev/null; echo "create_beside rc=$?"
echo "visible_from_outside_while_running=$(sudo -n ls /run/credentials/ 2>&1 | tr '\n' ' ')"
SVC
sudo systemd-run --wait --pipe --quiet --unit=$U -p LoadCredential=atkeys:$W/secret.bin -p SetCredential=inline:hi /bin/bash $W/svc.sh 2>&1
echo "systemd-run rc=$?"
echo "after_stop: $(sudo ls -la /run/credentials/ 2>&1 | grep -c $U) entries for $U"
rm -rf $W; echo "cleaned=$([ -e $W ] && echo no || echo yes)"
