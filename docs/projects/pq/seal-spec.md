# The seal: `atPQv1-base` and RFC 9180

Byte-level specification of the public-key encryption `pqSeal`/`pqOpen`
implement. Written so a second implementation can be built from this document
alone, without reading the Dart.

**Two constructions, selected by the envelope's first byte.**

| `ver` | What | Attested by |
|---|---|---|
| `0x01` | `atPQv1-base` — HPKE-shaped, Atsign-internal | our own vectors only |
| `0x02` | RFC 9180 Base mode, KEM `0x647A`, HKDF-SHA256, ChaCha20-Poly1305 | the IETF HPKE working group's published vectors |

Most of this document specifies `0x01`, because it is the one nobody else
describes. [Version 0x02](#version-0x02--rfc-9180) is at the end and is short,
for the same reason in reverse: it is RFC 9180, so the RFC is the specification
and what matters here is which suite and which framing.

Conformance vectors: `packages/at_chops/test/vectors/pq_seal_v1.json` (v1, run
by `pq_seal_conformance_test.dart`) and
`test/vectors/hpke_wg_0x647a_chacha.json` (v2, run by
`rfc9180_hpke_test.dart`).

## What version 0x01 is, and what it is not

`atPQv1-base` is an Atsign-internal envelope. It reuses RFC 9180 HPKE's
*shape* — a KEM, a KDF and an AEAD, with the KDF binding a caller-supplied
context — but it is **not RFC 9180 and not wire-compatible with it**. It has
its own key schedule and its own framing. Do not expect an off-the-shelf HPKE
library to interoperate.

The one place that distinction gets lost is the phrase "HPKE" in code comments
and dartdoc. Where this construction is meant, say `atPQv1-base` or
"HPKE-style"; an overclaim costs more credibility than a custom construction
plainly labelled. Version `0x02` is the one that may be called HPKE without
qualification.

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

## Version 0x02 — RFC 9180

`ver = 0x02` is **implemented**, and it is the real RFC 9180 rather than a
shape borrowed from it:

> RFC 9180 Base mode, KEM `0x647A` (X-Wing / MLKEM768-X25519), KDF `0x0001`
> (HKDF-SHA256), AEAD `0x0003` (ChaCha20-Poly1305).

That sentence is checkable, which is the entire reason for it. The key schedule
is §5.1 verbatim — `LabeledExtract`/`LabeledExpand` with `suite_id` inside every
label — and it reproduces the IETF HPKE working group's published `key`,
`base_nonce` and `exporter_secret` for that suite, along with all 10 of its
published encryptions. Those bytes are not ours; Go 1.26's `crypto/hpke`
vendors the same file.

**ChaCha20-Poly1305 rather than AES-256-GCM**, and the reason is evidence
rather than preference: the working group publishes `0x647A` vectors only at
AEAD `0x0003`. AES-GCM would mean shipping a suite with no published end-to-end
vector — "passes the IETF vectors except the AEAD arm" — and the FIPS story
that might have justified it is unavailable anyway, since X25519 key agreement
has no approved path and this hybrid is unclaimable under FIPS whatever AEAD
sits on top. `aad` is unused at every production call site and both AEADs are
Nk=32/Nn=12, so it was a free parameter.

Framing is unchanged: `ver || ctLen || enc || ct || tag`. Everything after the
3-byte header is exactly RFC 9180's `enc || ct`, so the Atsign part is a
3-byte frame around a conformant payload — the same relationship TLS and MLS
have to the constructions they carry.

Two properties worth stating because they are what keep the versions apart.
Version `0x01`'s domain separation is its `atPQv1-base` suite label; version
`0x02`'s is the `suite_id` inside every labelled extract and expand, so
`_suiteLabelFor` does not apply to it and raises if asked. And relabelling an
envelope from one version to the other fails to open in both directions, which
is asserted rather than assumed.

`pqSeal` takes a `version`, so a sender that knows what its recipient can open
— from the `suites` its key package advertises — chooses per call. Emitting a
version this build cannot open is refused rather than written.
