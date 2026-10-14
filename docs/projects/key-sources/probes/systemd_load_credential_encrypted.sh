set -u
W=$(sudo mktemp -d /root/kcprobe.XXXXXX); U=kcprobe-$(date +%s)
sudo python3 -c "import sys;sys.stdout.buffer.write(bytes((i*7+3)%251 for i in range(16384)))" | sudo tee $W/secret.bin >/dev/null
echo "--- arm3: tpm2 on a host without a TPM"
sudo systemd-creds encrypt --with-key=tpm2 --name=atkeys $W/secret.bin $W/tpm.cred 2>&1 | tail -1; echo "rc=${PIPESTATUS[0]}"
echo "--- arm1: host key, delivered with LoadCredentialEncrypted"
sudo systemd-creds encrypt --with-key=host --name=atkeys $W/secret.bin $W/atkeys.cred 2>&1 | tail -1; echo "encrypt rc=${PIPESTATUS[0]} blob=$(sudo stat -c %s $W/atkeys.cred) plaintext_in_blob=$(sudo grep -c "$(sudo head -c 32 $W/secret.bin | base64)" $W/atkeys.cred)"
sudo rm -f $W/secret.bin
sudo tee $W/svc.sh >/dev/null <<'SVC'
D="$CREDENTIALS_DIRECTORY"
echo "fs=$(stat -f -c %T "$D") dir=$(stat -c '%a %U' "$D") file=$(stat -c '%a %U %s' "$D/atkeys")"
echo "content_ok=$(python3 -c "d=open('$D/atkeys','rb').read();print(len(d)==16384 and d==bytes((i*7+3)%251 for i in range(len(d))))")"
grep " $D " /proc/self/mountinfo | awk '{print "mount_opts=" $6}'
echo x >> "$D/atkeys" 2>/dev/null; echo "append rc=$?"
touch "$D/new" 2>/dev/null; echo "create_beside rc=$?"
SVC
sudo systemd-run --wait --pipe --quiet --unit=$U -p LoadCredentialEncrypted=atkeys:$W/atkeys.cred /bin/bash $W/svc.sh 2>&1; echo "service rc=$?"
echo "after_stop: $(sudo ls /run/credentials/ 2>/dev/null | grep -c $U) entries for $U"
echo "--- arm2: tampered blob"
sudo cp $W/atkeys.cred $W/bad.cred; sudo python3 -c "p='$W/bad.cred';b=bytearray(open(p,'rb').read());b[len(b)//2]^=0xff;open(p,'wb').write(b)"
sudo systemd-run --wait --pipe --quiet --unit=$U-bad -p LoadCredentialEncrypted=atkeys:$W/bad.cred /bin/bash -c 'echo SERVICE_BODY_RAN' 2>&1 | tail -2; echo "service rc=${PIPESTATUS[0]}"
sudo journalctl -u $U-bad --no-pager -o cat | grep -iE "credential|decrypt|fail" | head -3
sudo systemctl reset-failed $U-bad 2>/dev/null
sudo rm -rf $W; echo "cleaned=$([ -e $W ] && echo no || echo yes)"
