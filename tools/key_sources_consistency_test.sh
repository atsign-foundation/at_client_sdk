#!/usr/bin/env bash
#
# Consistency test for docs/projects/key-sources and its probes.
#
# Would have caught:
#   * the systemd probe tampering a byte of the base64 TEXT instead of the
#     decoded ciphertext (systemd then rejects the file while base64-decoding
#     it, before any AES-GCM tag check, so the arm cannot support the
#     integrity row it is cited for);
#   * an unbound `HKDF(prf, "atkeys-kek")` label drifting from the profile's
#     atSign-bound `HKDF(prf, salt, "atkeys-kek|<atSign>")`;
#   * the passkey userHandle used as the WebAuthn PRF input, which arrives only
#     in the get() response and so costs a second prompt;
#   * the threat table marking whole-record rollback as fixed by AES-GCM;
#   * "eviction loses nothing" claimed while the enrollment id (assigned by
#     the atServer at enroll:request, needed by PKAM, the private record name
#     and the envelope AAD) is carried nowhere.
#
# Usage: bash tools/key_sources_consistency_test.sh
# Exits non-zero on the first failed check.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS="$ROOT/docs/projects/key-sources"
PROBE="$DOCS/probes/systemd_load_credential_encrypted.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. The probe's tamper arm must flip a byte of the DECODED blob and re-encode
#    it, so systemd reaches decryption (and its AES-GCM tag check) instead of
#    failing in READ_FULL_FILE_UNBASE64 on a non-base64 character.
# ---------------------------------------------------------------------------

# Extract the arm-2 python embedded in the probe and run it on a synthetic
# systemd-creds-style blob: base64 text wrapped at 79 columns.
arm2_py="$(sed -n '/arm2: tampered blob/,$p' "$PROBE" \
  | sed -n '/^sudo python3 -c "import base64,sys/,/\$W\/atkeys.cred \$W\/bad.cred$/p' \
  | sed -e '1s/^sudo python3 -c "//' -e '$s/" *\$W\/atkeys.cred \$W\/bad.cred$//')"
[ -n "$arm2_py" ] || fail "could not extract the tamper arm's python from $PROBE"
case "$arm2_py" in
  *base64*) ;;
  *) fail "extracted tamper arm python does not look like the base64 re-encode code" ;;
esac

python3 - "$WORK" <<'PY'
import base64, os, random, sys
random.seed(7)
blob = bytes(random.randrange(256) for _ in range(16400))
enc = base64.encodebytes(blob).decode()
wrapped = "\n".join(enc[i:i+79] for i in range(0, len(enc), 79)) + "\n"
work = sys.argv[1]
open(os.path.join(work, "atkeys.cred"), "w").write(wrapped)
PY
python3 -c "$arm2_py" "$WORK/atkeys.cred" "$WORK/bad.cred" \
  || fail "the probe's tamper arm python failed on a sample blob"

python3 - "$WORK" <<'PY' || fail "tampered credential check failed"
import base64, sys
work = sys.argv[1]
orig_text = open(f"{work}/atkeys.cred", "rb").read()
bad_text = open(f"{work}/bad.cred", "rb").read()

# The re-encoded file must be nothing but base64 and newlines: a flipped byte
# that is neither a base64 character nor whitespace makes systemd's
# unbase64mem_full fail before any decryption.
try:
    stripped = bytes(bad_text.translate(None, b"\n\r \t"))
    back = base64.b64decode(stripped, validate=True)
except Exception as e:
    sys.exit(f"FAIL: tampered credential is not valid base64 text: {e}")

orig = base64.b64decode(orig_text)
diff = [i for i in range(len(orig)) if orig[i] != back[i]]
if len(diff) != 1:
    sys.exit(f"FAIL: tampered blob differs in {len(diff)} decoded byte(s), expected 1")
print(f"tamper arm ok: valid base64, one decoded ciphertext byte flipped at {diff[0]}")
PY

# ---------------------------------------------------------------------------
# 2. Doc consistency: the three key-sources docs must not contradict the
#    profile's derivation.
# ---------------------------------------------------------------------------

cd "$DOCS"

# 2a. No unbound or unsalted custody labels: they drift from the atSign-bound
#     labels with salt and reopen the cross-atSign linkage the profile records as fixed.
if grep -n 'HKDF(prf, "atkeys-kek")\|HKDF(prf, "atkeys-record-id")' \
    design.md apkam-custody.md prf-server-keys-blob.md; then
  fail "unbound 'atkeys-kek'/'atkeys-record-id' label: bind it to the atSign"
fi
if grep -En 'HKDF\(prf,\s*"atkeys-kek|HKDF\(prf,\s*"atkeys-record-id|HKDF\(prf,\s*"at_auth/custody/auth-seed' \
    design.md apkam-custody.md prf-server-keys-blob.md; then
  fail "custody HKDF derivation drops the salt"
fi

# 2b. The userHandle must not be the WebAuthn PRF input: it arrives only in the
#     get() response, so it can only be the HKDF salt.
if grep -n 'PRF(userHandle\|PRF(device secret, userHandle' \
    design.md apkam-custody.md prf-server-keys-blob.md; then
  fail "userHandle used as the PRF input; it must be the HKDF salt"
fi

# 2c. Whole-record rollback must not be listed as fixed by the AEAD alone.
if grep -n 'rolled back | Envelope v2: AES-GCM, AAD = atSign, enrollmentId, version |$' \
    prf-server-keys-blob.md; then
  fail "rollback still claimed fixed by AES-GCM alone in the threat table"
fi
grep -q "Whole-record rollback" prf-server-keys-blob.md \
  || fail "whole-record rollback missing from the profile's Open table"

# 2d. The bootstrap record must carry only the enrollment id in the clear,
#     with the atKeys document stored exclusively in the private record.
bootstrap_json="$(sed -n '/The bootstrap record is/,/```$/p' prf-server-keys-blob.md | sed -n '/^```json$/,/^```$/p' | grep -v '^```' | tr -d '[:space:]')"
if [ "$bootstrap_json" != '{"enrollmentId":"<id>"}' ]; then
  fail "bootstrap record JSON block must contain only {\"enrollmentId\": \"<id>\"}, found: $bootstrap_json"
fi
if grep -C 3 -i 'flush' prf-server-keys-blob.md | grep -q 'public:_'; then
  fail "write-back in prf-server-keys-blob.md points at public:_ instead of atkeys.<enrollmentId>.a.__e"
fi
grep -C 3 -i 'flush' prf-server-keys-blob.md | grep -q 'atkeys\.<enrollmentId>\.a\.__e' \
  || fail "write-back in prf-server-keys-blob.md does not write to atkeys.<enrollmentId>.a.__e"
if grep -Eq 'public:_<recordId>.*envelope|envelope.*public:_<recordId>' prf-server-keys-blob.md; then
  fail "bootstrap record still described as carrying the envelope"
fi
grep -q 'atkeys\.<enrollmentId>\.a\.__e' prf-server-keys-blob.md \
  || fail "atKeys document private record location missing from prf-server-keys-blob.md"
grep -q "enrollment id in it in the clear" apkam-custody.md \
  || fail "apkam-custody.md does not cover where the enrollment id survives"
grep -q "enrollment id, which the atServer assigns" design.md \
  || fail "design.md does not cover where the enrollment id survives"

# 2e. Canonical atSign form in HKDF labels must specify as toAtsign() returns it.
grep -q 'as `toAtsign()` returns it' prf-server-keys-blob.md \
  || fail "prf-server-keys-blob.md does not specify canonical atSign via toAtsign()"
grep -q 'as `toAtsign()` returns it' design.md \
  || fail "design.md does not specify canonical atSign via toAtsign()"
grep -q 'as `toAtsign()` returns it' apkam-custody.md \
  || fail "apkam-custody.md does not specify canonical atSign via toAtsign()"

echo "key-sources consistency: all checks passed"
