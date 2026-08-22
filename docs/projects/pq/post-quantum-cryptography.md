# Post-quantum cryptography

What the Atsign Platform uses to authenticate, to exchange keys and to encrypt
data, and why each choice was made. The summary is the short answer; the
sections after it are the long one.

[Summary](#summary)
* [Authentication and signing: ML-DSA-65](#authentication-and-signing-ml-dsa-65)
* [Content encryption: AES-256-GCM](#content-encryption-aes-256-gcm)
* [Key exchange for the content encryption keys](#key-exchange-for-the-content-encryption-keys)
  * [Algorithm suites offered, as of Aug 2026](#algorithm-suites-offered-as-of-aug-2026)
  * [Standards and verification](#standards-and-verification)
* [Cryptographic agility](#cryptographic-agility)


[Detailed](#detailed)
* [Authentication and signing](#authentication-and-signing)
* [Key exchange for content keys](#key-exchange-for-content-keys)
* [Content encryption](#content-encryption)
* [Cryptographic agility](#cryptographic-agility-1)

## Summary

### Authentication and signing: ML-DSA-65
- Standard: [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final)
- OpenSSL implementation via FFI where the platform has OpenSSL 3.5 or later,
  pure-Dart everywhere else
- The pure-Dart implementation is verified against NIST's ACVP test vectors
  for FIPS 204, covering key generation, deterministic and hedged signing,
  and verification. The OpenSSL backend is cross-verified against it, with
  each implementation signing what the other verifies

### Content encryption: AES-256-GCM
- Symmetric encryption under AES-256 content keys in GCM mode, so a tampered
  value fails to decrypt rather than decrypting to something wrong

### Key exchange for the content encryption keys

#### Algorithm suites offered, as of Aug 2026
- **Default**: X-Wing with HKDF-SHA256 and ChaCha20-Poly1305 (HPKE KEM id
  0x647A). The default because it's where the industry has arrived: the
  ML-KEM-768 with X25519 pairing underneath it is what TLS deploys as
  X25519MLKEM768, the one hybrid group
  [RFC 10024](https://datatracker.ietf.org/doc/rfc10024/) marks as Recommended,
  and X-Wing is that pairing packaged as a standalone KEM. It's also the hybrid
  the IETF HPKE working group chose for HPKE, and the one Go's standard library
  carries as `MLKEM768X25519()`
- **Alternative**: ML-KEM-1024 with HKDF-SHA384 and AES-256-GCM (KEM id 0x0042),
  the strongest pure-lattice KEM NIST has standardised, for anyone who wants or
  requires a higher security level, a shorter specification chain, or no hybrid
  at all. It's the top of ML-KEM's 3 parameter sets and the suite is
  dialled to the 256-bit level throughout; it
  carries no combiner, so below the HPKE layer every element is a finalised
  standard; and some deployments reject hybrids as policy. Those are also the
  algorithms NSA's CNSA 2.0 profile names for key establishment, set out in
  [`draft-becker-cnsa2-tls-profile`](https://datatracker.ietf.org/doc/draft-becker-cnsa2-tls-profile/),
  NSA's own IETF profile, though matching that list is not the same as CNSA 2.0
  compliance, which turns on holding a CMVP-validated module

#### Standards and verification
- Standards status: the KEMs themselves are finalised, since ML-KEM is
  [FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) and X-Wing combines
  ML-KEM-768 with X25519. What isn't finalised is the placement of a
  post-quantum KEM inside HPKE. RFC 9180 covers Diffie-Hellman KEMs only, so
  both suites currently rest on IETF drafts,
  [`draft-ietf-hpke-pq`](https://datatracker.ietf.org/doc/draft-ietf-hpke-pq/)
  for the post-quantum HPKE algorithms and
  [`draft-irtf-cfrg-concrete-hybrid-kems`](https://datatracker.ietf.org/doc/draft-irtf-cfrg-concrete-hybrid-kems/)
  for the hybrid construction. We track the drafts and the registered
  codepoints rather than any private construction of our own, so finalisation
  should be a paperwork change rather than a re-implementation
- Both are verified against the IETF HPKE working group's published vectors,
  in both the pure-Dart and OpenSSL backends. These are third-party vectors,
  and Go's standard library `crypto/hpke` vendors the same file, so an independent
  implementation agrees on the bytes
- One naming wrinkle: X-Wing is being renamed MLKEM768-X25519 in the working
  group's draft, so the same 0x647A codepoint appears under both names
  depending on which document you're reading

### Cryptographic agility
Every encrypted record carries the id of the
  scheme that wrote it, so adding an algorithm is additive and lands in a minor
  version. See [cryptographic agility](#cryptographic-agility)

## Detailed
### Authentication and signing

Every atSign authenticates by proving it holds a private key, and it does that
with **ML-DSA-65** (FIPS 204), the lattice signature scheme NIST standardised
in 2024. It sits at NIST security category 3, roughly the 192-bit level.

The atServer issues a fresh challenge on each connection. The client signs that
challenge and the server verifies the signature against the public key in the
enrollment record. Freshness comes from the challenge and the channel comes
from TLS, so the signature is the only part a quantum adversary could attack.
That's why authentication needed a signature swap rather than a key exchange,
and it's why the move was cheap: the handshake shape didn't change at all, only
the algorithm that signs it.

ML-DSA-65 does 3 jobs here. It authenticates a device to its atServer (the
APKAM handshake). It signs the records an enrollment publishes about itself,
including its advertised key package, so a peer can check that what it's
reading really came from that enrollment. And it anchors the atSign's own
signing root, the user-owned key that ties the enrollments together.

The sizes are the cost of the move. An ML-DSA-65 public key is 1,952 bytes and
a signature is 3,309 bytes, against 256 bytes for an RSA-2048 signature.
Nothing in the protocol depends on signatures being small, so we took the
trade. One nicety is that ML-DSA signs a message directly, with no separate
hashing step, so the older pairing of a signature algorithm with a hash choice
disappears.

We use OpenSSL's implementation through FFI where the platform has OpenSSL 3.5
or later, and a pure-Dart implementation everywhere else. The pure-Dart one is
verified against NIST's ACVP test vectors for FIPS 204, covering key
generation, deterministic and hedged signing, and verification. The OpenSSL
backend is cross-verified against it, with each implementation signing what the
other verifies.

Standard: [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final)

### Key exchange for content keys

Data is encrypted under a symmetric content key, and that content key has to
reach the recipient. We do that with **HPKE**
([RFC 9180](https://www.rfc-editor.org/rfc/rfc9180.html)), the standard recipe
for encrypting to someone's public key without a round trip. That last part
matters for us, since a sender often needs to write to a device that's offline.

HPKE is 3 pieces bolted together. A KEM establishes a fresh shared secret from
the recipient's public key alone. A KDF turns that secret into an encryption
key. An AEAD then encrypts the payload, which in our case is the content key
itself. A named HPKE suite is one choice of each.

We support 2 suites, and which one an atSign uses is a deployment decision
rather than a per-message negotiation.

The default is **X-Wing with HKDF-SHA256 and ChaCha20-Poly1305** (HPKE KEM id
0x647A), and it's the default because it's where the rest of the industry has
arrived. The pairing underneath it, ML-KEM-768 with X25519, is the one the
ecosystem has settled on for post-quantum key establishment: in TLS it appears
as X25519MLKEM768, the single hybrid group
[RFC 10024](https://datatracker.ietf.org/doc/rfc10024/) marks as Recommended.
X-Wing is that same pairing packaged as a standalone KEM, with a SHA3-256
combiner of its own rather than TLS's concatenation, and it's the hybrid the
IETF HPKE working group chose for HPKE. Go's standard library carries it in
`crypto/hpke` as `MLKEM768X25519()`, described there as X-Wing. So the default
puts us on the construction everyone else is converging on rather than on
something we picked alone.

Being a hybrid, it stays secure as long as *either* component holds. That
covers the one scenario a pure lattice scheme doesn't, which is ML-KEM falling
to classical cryptanalysis before a quantum computer ever exists.
ChaCha20-Poly1305 is paired with it because it's the only AEAD the HPKE working
group publishes 0x647A test vectors for, and we'd rather deliver a suite that
has a published end-to-end vector.

The alternative is **ML-KEM-1024 with HKDF-SHA384 and AES-256-GCM** (KEM id
0x0042), the strongest pure-lattice KEM NIST has standardised, for anyone who
wants or requires a higher security level, a shorter specification chain, or no
hybrid at all.

ML-KEM is the only lattice KEM NIST has standardised, and 1024 is the top of
its 3 parameter sets. The suite is dialled to
the 256-bit level throughout, where the default pairs ML-KEM-768 with SHA-256.
For data with a confidentiality horizon measured in decades, and for anyone
taking harvest-now-decrypt-later at its most conservative, that's a straight
upgrade with no compliance story attached to it.

It also carries no combiner, so below the HPKE layer every element is a
finalised standard: FIPS 203, FIPS 197, SP 800-38D, RFC 5869 and FIPS 180-4.
That matters to anyone who has to write the algorithm chain into a risk
register or an assurance case rather than cite a draft. And some deployments
reject hybrids as policy, on the grounds that a second component is a second
thing to analyse rather than a hedge worth having.

Those are also the algorithms NSA's CNSA 2.0 profile names for key
establishment, set out in
[`draft-becker-cnsa2-tls-profile`](https://datatracker.ietf.org/doc/draft-becker-cnsa2-tls-profile/),
NSA's own IETF profile, since the CNSA 2.0 documents on `media.defense.gov`
refuse automated fetching. Matching that list is not the same as CNSA 2.0
compliance, which turns on holding a CMVP-validated module, and the same
profile requires ML-DSA-87 for signatures where we use ML-DSA-65.

An atSign configured this way still talks to hybrid peers, since a sender
always follows what the recipient advertised.

Both suites are verified against the IETF HPKE working group's published
vectors, in both the pure-Dart and OpenSSL backends. These are third-party
vectors, and Go's standard library `crypto/hpke` vendors the same file, so an independent
implementation agrees on the bytes.

On standards status, the KEMs themselves are finalised, since ML-KEM is FIPS
203 and X-Wing combines ML-KEM-768 with X25519. What isn't finalised is the
placement of a post-quantum KEM inside HPKE. RFC 9180 covers Diffie-Hellman
KEMs only, so both suites currently rest on IETF drafts,
`draft-ietf-hpke-pq` for the post-quantum HPKE algorithms and
`draft-irtf-cfrg-concrete-hybrid-kems` for the hybrid construction. We track
the drafts and the registered codepoints (0x647A and 0x0042) rather than any
private construction of our own, so finalisation should be a paperwork change
rather than a re-implementation. One naming wrinkle: X-Wing is being renamed
MLKEM768-X25519 in the working group's draft, so the same 0x647A codepoint
appears under both names depending on which document you're reading.

Standards:

- HPKE, RFC 9180: <https://www.rfc-editor.org/rfc/rfc9180.html>
- HPKE codepoint registry: <https://www.iana.org/assignments/hpke/hpke.xhtml>
- PQ algorithms for HPKE (draft):
  <https://datatracker.ietf.org/doc/draft-ietf-hpke-pq/>
- X-Wing as MLKEM768-X25519 (CFRG draft):
  <https://datatracker.ietf.org/doc/draft-irtf-cfrg-concrete-hybrid-kems/>
- ML-KEM, FIPS 203: <https://csrc.nist.gov/pubs/fips/203/final>
- HKDF, RFC 5869: <https://www.rfc-editor.org/rfc/rfc5869.html>
- ChaCha20-Poly1305, RFC 8439: <https://www.rfc-editor.org/rfc/rfc8439.html>
- The same hybrid in TLS, RFC 10024:
  <https://datatracker.ietf.org/doc/rfc10024/>
- CNSA 2.0 profile (NSA's own IETF draft):
  <https://datatracker.ietf.org/doc/draft-becker-cnsa2-tls-profile/>

### Content encryption

Application data is encrypted with **AES-256-GCM** under a symmetric content
key. This layer is entirely symmetric and never touches public-key crypto,
which is what keeps the cost of a write flat no matter how many people can read
the data.

A content key is generated once and sealed once. The sealed copy is written as
its own small record, and every value encrypted under that key cites the key by
its id, a SHA-256 prefix we call the `ckKid`. So a recipient does one unwrap and
can then read every value under that key. Sealing per value instead would
multiply the public-key work by the number of writes for no benefit.

AES-256-GCM gives us authenticated encryption, so a value that has been
tampered with fails to decrypt rather than decrypting to something wrong.
Anyone who has watched a padding-oracle attack unfold will appreciate why that
property is not optional. GCM is also hardware-accelerated on almost every
machine we run on.

Each stored value carries the id of the scheme that wrote it, so a reader
routes by what the record says rather than by what the reader happens to
prefer. That's what lets post-quantum records and older records coexist while a
fleet upgrades, and it's why the read path moved to the new scheme well before
the write path did.

The older scheme, still readable, wrapped an AES key with RSA-2048 and stored
it inline with each value. The separation of a content key from the data it
protects is the main structural change, and the reason a rotation now costs one
small record rather than a rewrite of everything.

Standards:

- AES, FIPS 197: <https://csrc.nist.gov/pubs/fips/197/final>
- GCM mode, NIST SP 800-38D: <https://csrc.nist.gov/pubs/sp/800/38/d/final>

### Cryptographic agility

None of the algorithm choices above are baked in. Every encrypted record
carries the id of the scheme that wrote it and every advertised key carries its
own algorithm id, so a reader routes by what the record says rather than by
what the reader prefers, and it skips any entry whose algorithm it doesn't
recognise instead of failing. Adding a new KEM, signature scheme or AEAD is
therefore additive: it lands in a minor version, older clients keep reading
everything they could read before, and no stored record changes meaning.

Which algorithms an atSign advertises, and which it will encrypt to, are
configuration rather than code, and an enrollment can amend its own advertised
set after the fact. So moving the default is a staged change we can make in
minor releases too, with the read side going out across the fleet first and the
write side following once, rather than a version boundary everyone has to cross
at the same moment.
