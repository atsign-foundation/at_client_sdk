# The seal: RFC 9180 in an Atsign envelope

Byte-level specification of the public-key encryption `pqSeal`/`pqOpen`
implement. Written so a second implementation can be built from this document
plus RFC 9180, without reading the Dart.

**Two constructions, selected by the envelope's first byte.**

| `ver` | What | Attested by |
|---|---|---|
| `0x02` | RFC 9180 Base mode, KEM `0x647A`, HKDF-SHA256, ChaCha20-Poly1305 | the IETF HPKE working group's published vectors |
| `0x03` | RFC 9180 Base mode, KEM `0x0042`, HKDF-SHA384, AES-256-GCM | the IETF HPKE working group's published vectors |

They differ in their **KEM**, and that is why they are separate versions rather
than one version carrying a suite field. Nothing can seal ML-KEM-1024 to a
hybrid encapsulation key or the reverse, so the KEM is already fixed by
whichever key the recipient advertised — the version byte therefore names the
whole suite, and an opener needs no input beyond the byte it already reads
first.

Both are RFC 9180 Base mode verbatim, so **the RFC is the specification** and
what this document adds is the Atsign envelope around it: which suite each
version names, how the envelope is framed, and what the error model promises.

Conformance vectors, both under `packages/at_chops/test/vectors/`:

| File | Covers | Run by |
|---|---|---|
| `hpke_wg_0x647a_chacha.json` | `ver 0x02`, the HPKE WG's published `0x647A` rows | `rfc9180_hpke_test.dart` |
| `hpke_wg_0x0042_mlkem1024.json` | `ver 0x03`, the HPKE WG's published `0x0042` rows | `rfc9180_hpke_test.dart`, `ml_kem_1024_test.dart` |

Neither file was generated here. That is the point of them: a self-generated
vector attests that two implementations agree with each other, while these
attest that both agree with the working group.

## Version 0x01, retired

`ver 0x01` was `atPQv1-base` — X-Wing under a bespoke HKDF-SHA256 key schedule
with AES-256-GCM, HPKE-*shaped* but not RFC 9180 and not wire-compatible with
it. Most of this document used to specify it, because it was the construction
nobody else described.

It was removed outright rather than deprecated. It shared its KEM with `0x02`,
so it was never algorithm diversity — a break in X-Wing took out both, and the
genuine hedge is `0x03`'s different KEM. What it uniquely offered was AES-256-GCM
where `0x02` uses ChaCha20-Poly1305, and what it sealed is a 32-byte content
key, at which size the KEM dominates the AEAD by orders of magnitude. Against
that it cost a homegrown key schedule attested only by vectors we generated
ourselves.

Removing a supported version turns records already sealed under it into
permanent version-mismatch failures. That was safe here because no published
build contains the subsystem that writes durable sealed records, so nothing
outside this repository held one; the published envelopes that could carry it
expire on a 7-day ttl. The full reasoning is
[decisions 110](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18).

The byte-level specification of `0x01`, its key schedule and its 95 conformance
rows are in this file's git history; they are not reproduced here, because a
specification for a construction nothing can emit or open invites someone to
build one.

## Wire format

```
envelope = ver || ctLen || kemCt || aeadCiphertext || tag
```

| Field | Size | Value |
|---|---|---|
| `ver` | 1 byte | `0x02` or `0x03` |
| `ctLen` | 2 bytes | length of `kemCt`, big-endian. `0x0460` (1120) for X-Wing, `0x0620` (1568) for ML-KEM-1024 |
| `kemCt` | `ctLen` bytes | the KEM encapsulation |
| `aeadCiphertext` | same length as the plaintext | the version's AEAD ciphertext |
| `tag` | 16 bytes | the version's AEAD authentication tag |

So the total is `3 + ctLen + |plaintext| + 16`. There is no nonce on the wire,
because it is derived; and no associated data on the wire, because the caller
supplies it on both sides.

A shorter-than-3-byte envelope, or one whose declared `ctLen` overruns the
buffer, is malformed.

## Errors

Three outcomes, and a caller told to catch one must never receive another:

| Outcome | When |
|---|---|
| version mismatch | `ver` is not in the supported set |
| malformed envelope | too short, `ctLen` overruns, or decapsulation rejects the input's shape |
| authentication failure | anything the AEAD refuses |

## Versioning

`ver` is the first byte and is checked before anything else, so a future
construction arrives as a typed refusal rather than a garbled decrypt. Above
it, `appMetadata.providerId` names every algorithm a reader needs code for, so
a different construction can coexist per value with reads staying universal.

**Which version a sender emits is negotiated, not fixed.** `pqSeal` takes the
version from its caller, and every advertised recipient key in the Atsign
Protocol — the enrollment key package and the published nskey advertisement —
carries a `suites` list naming the constructions its holder can **open**. A
sender picks the strongest entry both sides list and maps it to a version. That
is what let `0x02` replace `0x01` between two modern peers with no fleet-wide
upgrade in between, and what later made it safe to drop `0x01` outright.

A record that carries **no** `suites` list is refused at the parse rather than
defaulted. Guessing a construction on a holder's behalf is how a sender comes
to seal something that holder cannot unwrap.

No mutually supported construction is a **refusal**, not a fallback to the
sender's own preference: an envelope the recipient cannot unwrap surfaces on
*their* side as an authentication failure that names nothing, which is the one
outcome this document's error model deliberately cannot distinguish.

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

## Version 0x03 — RFC 9180 without the hybrid

`ver = 0x03` is **implemented**. The suite is

> RFC 9180 Base mode, KEM `0x0042` (ML-KEM-1024), KDF `0x0002` (HKDF-SHA384),
> AEAD `0x0002` (AES-256-GCM).

It exists for its **citation** rather than its strength. Used alone, ML-KEM-1024
is the only key establishment here whose specification chain contains no draft
at all — FIPS 203 for the KEM, SP 800-227 section 4.3 for feeding its shared
secret to a key-derivation function, SP 800-56C for the derivation — where every
hybrid's *combiner* is specified only in an IETF draft. It is also CNSA 2.0's
mandated parameter set, and CNSA 2.0 treats hybrids as non-compliant.

What it gives up is the hedge against ML-KEM falling to **classical**
cryptanalysis before a quantum computer exists. It loses nothing against a
quantum adversary, since a hybrid's traditional half is Shor-broken anyway.
State that in that order or a reviewer will correct it.

**The KDF and AEAD are not a free choice.** KEM `0x0042` has exactly two
published HPKE rows and only one at a 256-bit AEAD, so HKDF-SHA384 is what buys
a third-party end-to-end vector instead of a self-generated one. It is also the
combination CNSA 2.0 names — ML-KEM-1024 with SHA-384 and AES-256 — which is the
market this version exists for.

Sizes, for a port: 64-byte seed (`d || z`), 1568-byte encapsulation key,
1568-byte ciphertext, 32-byte shared secret. Note that a 1568-byte `ctLen` is
larger than X-Wing's 1120, which is worth a round trip of its own: it pins that
an implementation reads `ctLen` from the KEM output rather than assuming a
constant.

**The private is persisted as the 64-byte seed, never as the secret key.**
ML-KEM-1024's secret key is a 3168-byte expanded decapsulation key that no
seeded call reproduces and that nothing turns back into a public half. Two
independent IETF documents settle the question in favour of the seed. An
implementation that stores the expanded key has a working system until its first
restart, at which point every record sealed to that key is unopenable — with no
error at the moment the mistake is made.

Framing and error behaviour are exactly `0x01`'s and `0x02`'s:
`ver || ctLen || enc || ct || tag`, with everything after the 3-byte header
being RFC 9180's `enc || ct`. Relabelling a `0x03` envelope as `0x02` fails to
open, which proves the version byte selects the suite rather than describing it.

One thing a port must not get wrong: **HKDF-SHA384, not SHA-256**. RFC 5869
publishes vectors for SHA-256 and SHA-1 only, so this KDF has no standalone
attestation — its evidence is the `0x0042` key schedule end to end, where `key`,
`base_nonce` and the 48-byte exporter secret all reproduce the working group's
published bytes. A build whose KDF dispatch ignored `kdf_id` and always used
SHA-256 would produce a different key from the same shared secret, and nothing
but that end-to-end check would say so.
