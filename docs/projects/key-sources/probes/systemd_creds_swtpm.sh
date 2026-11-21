set -u
apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq systemd swtpm swtpm-tools tpm2-tools libtss2-tcti-swtpm0 python3 >/dev/null 2>&1; echo "install=$?"
systemd-creds --version | head -1
start_tpm() { # $1 = state dir, $2 = port
  mkdir -p $1; swtpm_setup --tpm2 --tpmstate $1 --createek --create-ek-cert --create-platform-cert --lock-nvram >/dev/null 2>&1 || swtpm_setup --tpm2 --tpmstate $1 >/dev/null 2>&1
  swtpm socket --tpm2 --tpmstate dir=$1 --server type=tcp,port=$2 --ctrl type=tcp,port=$(($2+1)) --flags startup-clear --daemon; sleep 1; }
start_tpm /tmp/tpmA 2321
start_tpm /tmp/tpmB 2331
python3 -c "import sys;sys.stdout.buffer.write(bytes((i*7+3)%251 for i in range(16384)))" > /tmp/secret.bin
echo "--- arm1: seal to TPM A, unseal on TPM A"
systemd-creds encrypt --with-key=tpm2 --tpm2-device=swtpm:host=127.0.0.1,port=2321 --name=atkeys /tmp/secret.bin /tmp/sealed.cred 2>&1 | tail -2; echo "encrypt rc=${PIPESTATUS[0]} size=$(stat -c %s /tmp/sealed.cred 2>/dev/null)"
systemd-creds decrypt --tpm2-device=swtpm:host=127.0.0.1,port=2321 --name=atkeys /tmp/sealed.cred /tmp/out1.bin 2>&1 | tail -2; echo "decrypt rc=${PIPESTATUS[0]} same=$(cmp -s /tmp/secret.bin /tmp/out1.bin && echo true || echo false)"
echo "--- arm2 (negative control): unseal the same blob on TPM B"
systemd-creds decrypt --tpm2-device=swtpm:host=127.0.0.1,port=2331 --name=atkeys /tmp/sealed.cred /tmp/out2.bin 2>&1 | tail -2; echo "decrypt rc=${PIPESTATUS[0]} wrote=$([ -s /tmp/out2.bin ] && echo yes || echo no)"
echo "--- arm3: host key only (no TPM)"
systemd-creds encrypt --with-key=host --name=atkeys /tmp/secret.bin /tmp/host.cred 2>&1 | tail -1; echo "encrypt rc=${PIPESTATUS[0]}"
systemd-creds decrypt --name=atkeys /tmp/host.cred /tmp/out3.bin 2>&1 | tail -1; echo "decrypt rc=${PIPESTATUS[0]} same=$(cmp -s /tmp/secret.bin /tmp/out3.bin && echo true || echo false)"
echo "host key file: $(ls -l /var/lib/systemd/credential.secret 2>&1 | awk '{print $1, $NF}')"
