// Verifies test/vectors/jws_envelope.json with panva's `jose` — an
// implementation that is not ours, which is the point: it turns "the signed
// envelope is RFC 7515 general JSON serialization" from a claim into a
// runnable check. jose is handed the envelope whole, exactly as written: the
// shape carries no member of our own for a compliant verifier to ignore.
//
//   cd tool && npm install --no-save jose && node verify_jws_vectors.mjs
//
// The RS256 arm runs on any Node jose supports. The ML-DSA-65 arm needs a
// Node whose bundled OpenSSL is >= 3.5 (Node 24.2 bundles 3.0.16, so it
// FAILs there at key import — the runtime, not the vector). Until such a
// Node is at hand, verify that arm with an OpenSSL >= 3.5 CLI directly:
// the signing input is ASCII(protected + '.' + payload), the signature is
// base64url, and `openssl pkeyutl -verify -rawin` over an SPKI-wrapped
// public key checks it — see docs/projects/pq/decisions.md 60.4 for the
// exact run this was proven with. Exits non-zero on any failure.
import { readFileSync } from 'node:fs';
import { createPublicKey } from 'node:crypto';
import { generalVerify } from 'jose';

const vectors = JSON.parse(
  readFileSync(new URL('../test/vectors/jws_envelope.json', import.meta.url)),
);
const expectedPayload = JSON.stringify(vectors.payload);
let failures = 0;

const ok = (name, detail = '') =>
  console.log(`PASS ${name}${detail ? ` — ${detail}` : ''}`);
const fail = (name, err) => {
  failures += 1;
  console.error(`FAIL ${name} — ${err}`);
};

async function verifyArm(name, envelope, key, expectedAlg) {
  // generalVerify walks the `signatures` array and returns the entry it
  // verified — the shape's own reader takes the first entry, and one entry is
  // what a signer writes today.
  const { payload, protectedHeader } = await generalVerify(envelope, key);
  const decoded = Buffer.from(payload).toString('utf8');
  if (decoded !== expectedPayload) {
    throw new Error(`payload mismatch: ${decoded}`);
  }
  if (protectedHeader.alg !== expectedAlg) {
    throw new Error(`alg mismatch: ${protectedHeader.alg}`);
  }
  ok(name, `alg=${protectedHeader.alg}, kid=${protectedHeader.kid}`);

  // The tamper arm, so a verifier that accepts everything cannot pass.
  const tampered = {
    ...envelope,
    payload: Buffer.from(expectedPayload.replace('1', '2'))
      .toString('base64url'),
  };
  try {
    await flattenedVerify(tampered, key);
    fail(`${name} (tamper)`, 'a tampered payload verified');
  } catch {
    ok(`${name} (tamper)`, 'tampered payload refused');
  }
}

// --- RS256: the _apsk value is base64 SPKI DER ---
try {
  const rsaKey = createPublicKey({
    key: Buffer.from(vectors.rs256.apskPublicKey, 'base64'),
    format: 'der',
    type: 'spki',
  });
  await verifyArm('RS256', vectors.rs256.envelope, rsaKey, 'RS256');
} catch (e) {
  fail('RS256', e);
}

// --- ML-DSA-65: wrap the raw public key in SPKI DER (OID
// 2.16.840.1.101.3.4.3.18, no parameters, BIT STRING body) ---
function mlDsa65Spki(raw) {
  const derLen = (n) =>
    n < 128
      ? Buffer.from([n])
      : Buffer.concat([
          Buffer.from([0x82, (n >> 8) & 0xff, n & 0xff]),
        ]);
  const oid = Buffer.from([
    0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x03, 0x12,
  ]);
  const algId = Buffer.concat([Buffer.from([0x30]), derLen(oid.length), oid]);
  const bitString = Buffer.concat([
    Buffer.from([0x03]),
    derLen(raw.length + 1),
    Buffer.from([0x00]),
    raw,
  ]);
  const body = Buffer.concat([algId, bitString]);
  return Buffer.concat([Buffer.from([0x30]), derLen(body.length), body]);
}

try {
  const mlDsaKey = createPublicKey({
    key: mlDsa65Spki(Buffer.from(vectors.mlDsa65.publicKey, 'base64')),
    format: 'der',
    type: 'spki',
  });
  await verifyArm('ML-DSA-65', vectors.mlDsa65.envelope, mlDsaKey, 'ML-DSA-65');
} catch (e) {
  fail('ML-DSA-65', e);
}

process.exit(failures === 0 ? 0 : 1);
