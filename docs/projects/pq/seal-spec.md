# The `atPQv1-base` seal

Byte-level specification of the public-key encryption `pqSeal`/`pqOpen`
implement. Written so a second implementation can be built from this document
alone, without reading the Dart.

Conformance vectors: `packages/at_chops/test/vectors/pq_seal_v1.json`, run by
`packages/at_chops/test/pq_seal_conformance_test.dart`.

## What this is, and what it is not

`atPQv1-base` is an Atsign-internal envelope. It reuses RFC 9180 HPKE's
*shape* — a KEM, a KDF and an AEAD, with the KDF binding a caller-supplied
context — but it is **not RFC 9180 and not wire-compatible with it**. It has
its own key schedule and its own framing. Do not expect an off-the-shelf HPKE
library to interoperate.

The one place that distinction gets lost is the phrase "HPKE" in code comments
and dartdoc. Where this construction is meant, say `atPQv1-base` or
"HPKE-style"; an overclaim costs more credibility than a custom construction
honestly labelled.

The primitives are standard and separately attested. The composition — the
suite label, the two derivation labels, the empty salt, the concatenation
order and the framing — is attested by nothing outside this repository, which
is why the vector file exists.

## The suite

| Role | Algorithm |
|---|---|
| KEM | X-Wing (ML-KEM-768 + X25519), IANA HPKE KEM id `0x647A` |
| KDF | HKDF-SHA256 (RFC 5869) |
| AEAD | AES-256-GCM (SP 800-38D), 12-byte nonce, 16-byte tag |

The KEM is a parameter of `pqSeal` rather than fixed by the construction, but
X-Wing is the only one used in production and the only one the vectors cover.
Its sizes: 32-byte seed secret key, 1216-byte public key, 1120-byte
ciphertext, 32-byte shared secret.

## Wire format

```
envelope = ver || ctLen || kemCt || aeadCiphertext || tag
```

| Field | Size | Value |
|---|---|---|
| `ver` | 1 byte | `0x01` |
| `ctLen` | 2 bytes | length of `kemCt`, big-endian. `0x0460` (1120) for X-Wing |
| `kemCt` | `ctLen` bytes | the KEM encapsulation |
| `aeadCiphertext` | same length as the plaintext | AES-256-GCM ciphertext |
| `tag` | 16 bytes | AES-256-GCM authentication tag |

So the total is `3 + ctLen + |plaintext| + 16`. There is no nonce on the wire,
because it is derived; and no associated data on the wire, because the caller
supplies it on both sides.

A shorter-than-3-byte envelope, or one whose declared `ctLen` overruns the
buffer, is malformed.

## Key schedule

Let `ss` be the KEM shared secret (32 bytes for X-Wing) and `info` the
caller's context, which may be absent.

```
suiteLabel = "atPQv1-base"                     ; 11 bytes ASCII
           = 61 74 50 51 76 31 2d 62 61 73 65

suiteInfo  = suiteLabel || info                ; info absent means zero bytes

key   = HKDF-SHA256(ikm = ss, salt = <empty>, info = suiteInfo || 0x01, L = 32)
nonce = HKDF-SHA256(ikm = ss, salt = <empty>, info = suiteInfo || 0x02, L = 12)
```

Four details a port gets wrong if they are not stated:

- **An absent `info` and a zero-length `info` are the same thing.** Production
  callers on the nskey path pass no `info` at all, and the vectors pin both
  forms to the same output.
- **The salt is empty**, not 32 zero bytes. RFC 5869 defines a zero-length
  HMAC key as equivalent to the block-length zero-filled default, so the two
  agree — but only if the implementation follows the RFC rather than
  substituting zeros of its own choosing.
- **The suite label is compared as bytes, not characters.** It is pure ASCII,
  so UTF-8 and UTF-16 code units happen to agree; a port that encodes it as
  UTF-16 anyway will disagree the moment the label changes.
- **Nothing is length-prefixed.** `suiteLabel`, `info` and the trailing
  `0x01`/`0x02` are raw-concatenated. This is a difference from RFC 9180's
  `LabeledExtract`/`LabeledExpand`, which prefix a version string, a suite id
  and a label length.

HKDF-SHA256 is the textbook construction: `PRK = HMAC-SHA256(salt, ikm)`, then
`T(i) = HMAC-SHA256(PRK, T(i-1) || info || i)` with a single-byte counter
starting at 1, truncated to `L`.

`ver` selects the suite label, and each version must have its own. That is what
keeps a future construction's keys domain-separated from this one's even if
dispatch were wrong.

## Seal

Given a recipient public key, a plaintext, and optional `info` and `aad`:

1. `(kemCt, ss) = KEM.Encapsulate(recipientPublicKey)` — fresh randomness per
   call. There is no derandomised variant in the public API.
2. Derive `key` and `nonce` from `ss` and `info` as above, at `ver = 0x01`.
3. `aeadCiphertext || tag = AES-256-GCM-Seal(key, nonce, aad, plaintext)`,
   where an absent `aad` means zero bytes.
4. Emit the wire format.

Every seal encapsulates afresh, so the nonce is never reused under a given key:
each `(key, nonce)` pair is used exactly once, for exactly one message. There
is no sequence number and no multi-message context.

## Open

Given the recipient secret key, an envelope, and the same `info` and `aad`:

1. Refuse an envelope shorter than 3 bytes as malformed.
2. Read `ver`. **Refuse an unrecognised version before parsing anything
   else** — a version check that happens after a length parse reports a
   version mismatch as a corrupt buffer.
3. Read `ctLen`; refuse if `3 + ctLen + 16` exceeds the envelope length.
4. `ss = KEM.Decapsulate(recipientSecretKey, kemCt)`. A wrong-length secret key
   or ciphertext is a malformed envelope, not a crash.
5. Derive `key` and `nonce` from `ss` and the envelope's own `ver`.
6. AES-256-GCM open. Any failure is an authentication failure.

**Every AEAD-level failure collapses to one outcome, deliberately.** A wrong
key, a tampered ciphertext, a mismatched `info` and a mismatched `aad` are
indistinguishable to the caller. X-Wing rejects implicitly — decapsulating with
the wrong key yields a well-formed but different shared secret rather than an
error — so there is no wrong-key oracle to expose, and adding one would be a
downgrade.

## Errors

Three outcomes, and a caller told to catch one must never receive another:

| Outcome | When |
|---|---|
| version mismatch | `ver` is not in the supported set |
| malformed envelope | too short, `ctLen` overruns, or decapsulation rejects the input's shape |
| authentication failure | anything the AEAD refuses |

## Conformance

`pq_seal_v1.json` carries two kinds of row.

**`keySchedule`** — 15 rows of `(sharedSecret, info) → (key, nonce)`, covering
an all-zero shared secret, an all-ones one, a real X-Wing output, and five
contexts including the two production ones, an absent `info`, a zero-length
`info` and a non-ASCII one. Check these first: a schedule mismatch otherwise
surfaces only as an AEAD authentication failure, which says nothing about
which side is wrong.

**`envelopes`** — 80 rows of `(recipientSeed, info, aad, plaintext,
envelope)`. Each must open to its plaintext under the stated context. Plaintext
lengths include 0, 1, 44 and 1000 bytes; recipient keys come from two fixed
X-Wing seeds so the whole row is reproducible from the file.

The seal direction cannot be checked byte-for-byte across implementations,
because encapsulation draws fresh randomness and the KEM interface exposes no
derandomised variant. Check it the other way: seal in one implementation, open
in the other. A conformant sealer produces envelopes any conformant opener
accepts.

Note what these vectors are worth. They are **self-generated** — no third party
publishes vectors for an Atsign-internal construction — so they attest that two
implementations agree, and nothing more. That is still the property that
matters most here: the tagged `_apsk` shape carried a version field and still
forked across two atServer implementations inside a week, because its only
specification was a Dart function. A version field did not catch it and a
written specification would not have. A vector file turns red on the next
build.

## Versioning

`ver` is the first byte and is checked before anything else, so a future
construction arrives as a typed refusal rather than a garbled decrypt. Above
it, `appMetadata.providerId` names every algorithm a reader needs code for, so
a different construction can coexist per value with reads staying universal.

`ver = 0x02` is reserved for an RFC 9180 encoding. Two things to know before
using it. The suite label must change with the version, or the two
constructions share derived keys. And there is currently no **write-side**
version selector: `_envelopeVersion` is a single constant, so at_chops cannot
emit `0x01` to old readers and `0x02` to new ones until one is added.
