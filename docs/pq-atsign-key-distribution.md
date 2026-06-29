# Same-atSign secret conveyance: requesting a named secret from peer clients

**Status:** proposal / working doc (not plan-of-record). Lives in `docs/`.

**The general problem (the right frame).** Distributing the atSign-level PQ private
key to Alice's existing clients is one instance of a single reusable primitive:

> **A client needs a *named secret*. At least one of Alice's other clients is
> expected to hold it. How does the requester obtain it — PQ-safely, with the
> server never able to read it?**

Almost every secret conveyance in the PQ design is this shape: the atSign-level PQ
private key, a per-namespace `nskey` private key, a rotation epoch key, a master
seed. So the deliverable is **one request/serve primitive over the secret-sharing
substrate**, plus a thin **bootstrap** layer for the one case the primitive cannot
cover — *no peer holds the secret yet* (someone must create it exactly once). The
atSign-level PQ key is the worked example throughout.

**Secrets are namespaced** — a request is scoped to a namespace, and that namespace is
the authorisation boundary for who may receive it (the same APKAM enrollment scoping
the atServer already enforces). The atSign-level PQ key is the **sole root
(no-namespace) exception**: it is conveyed to *every* APKAM keypair, like the legacy default
encryption private key it replaces.

## Table of contents

- [1. The primitive — `requestSecret(name)`](#1-the-primitive--requestsecretname)
  - [Substrate API this maps onto (prototyped on `gkc-pqmls-spike`, not yet landed)](#substrate-api-this-maps-onto-prototyped-on-gkc-pqmls-spike-not-yet-landed)
  - [Details the primitive must pin down](#details-the-primitive-must-pin-down)
- [2. Why the easy conveyances don't qualify](#2-why-the-easy-conveyances-dont-qualify)
- [3. Worked example — the atSign-level PQ key](#3-worked-example--the-atsign-level-pq-key)
  - [Naming](#naming)
- [4. Bootstrap — when *no* peer holds the secret yet](#4-bootstrap--when-no-peer-holds-the-secret-yet)
- [5. Upgrading existing clients — the three scenarios](#5-upgrading-existing-clients--the-three-scenarios)
  - [Legacy APKAM deletion & what revocation means](#legacy-apkam-deletion--what-revocation-means)
  - [Where the PQ APKAM key lives (storage & host binding)](#where-the-pq-apkam-key-lives-storage--host-binding)
- [6. End-to-end sequence (atSign-level PQ key)](#6-end-to-end-sequence-atsign-level-pq-key)
- [7. Edge cases](#7-edge-cases)
- [8. To verify / cross-tier notes](#8-to-verify--cross-tier-notes)
- [9. How this maps to the plan (no plan edits yet)](#9-how-this-maps-to-the-plan-no-plan-edits-yet)

## 1. The primitive — `requestSecret(name)`

Every Alice **APKAM keypair** on a PQ build is accompanied by a **key package**: an
X-Wing public key (`pub`, `kpid` = kid of its X-Wing public key) whose private half is
generated locally and **never leaves the keyfile**. The key package is **not published** —
it is carried in the per-APKAM enrollment record (`<E>.<apkamId>.pqapkam.__manage@alice`)
next to the ML-DSA APKAM public key, registered by the authenticated APKAM keypair. The
trust anchor is that enrollment-record registration; the key package is discovered only via
the gated `enroll:listfornamespace` verb (`pq-secret-push.md`), never as a public at-key.

Given that, the primitive is:

1. **Request.** The requester **discovers** the namespace's authorised APKAM keypairs via
   the gated atServer verb `enroll:listfornamespace:<ns>` (`pq-secret-push.md` §2), which
   returns the authorised enrollments and their per-APKAM key packages, and **fans out** a
   sealed request to each — there is no keyless broadcast: each request is a targeted
   `pqSeal`-ed envelope addressed to a peer's `kpid`, carrying the requester's *own* `kpid`
   so responders know where to seal the answer. (The root PQ key is the no-namespace
   exception — §3.)
2. **Serve.** Each peer, on seeing the request, checks its `SecretStore`. If it holds
   the secret *and* the requester's enrollment is authorised for that **namespace**
   (below), it `pqSeal`s the secret to the requester's key package (by `kpid`) and writes
   the envelope back.
3. **Receive.** The requester `waitForSecret(name)` resolves on the first valid
   response.
4. **Verify.** The envelope is APKAM-signed, proving the responder is a genuine Alice
   client. For a keypair secret, the requester also re-derives the public key from
   the received private key and checks it equals the published public key — proving
   it is *the* key, not an injected one.
5. **Store.** The verified secret lands in the APKAM keypair's updatable keystore (its
   updatable `.atKeys`, working name *WritableAtKeys* — deferred, not a landed type), keyed
   by `name` (+ version).

This is PQ-safe by construction: the seal is X-Wing (hybrid PQ) to a public key whose
private half never transited; nothing in the path depends on RSA-2048 confidentiality.

### Substrate API this maps onto (prototyped on `gkc-pqmls-spike`, not yet landed)

The substrate prototyped on the spike (`packages/at_client/lib/src/secret_sharing/`,
**WP-SS — not yet landed**) has the pieces; the primitive is mostly composition, not new
crypto:

| Need                                 | Prototyped API (WP-SS)                                                     |
|--------------------------------------|----------------------------------------------------------------------------|
| Per-APKAM X-Wing identity            | key package (`registerClient(...)`)                                        |
| Request a secret                     | `requestSecretsFromNamespace(...)` → `waitForSecret(...)`                  |
| Serve a secret (seal to a requester) | `shareSecretWith(keyPackage, Secret)`, `shareAllSecretsWith(to, {excludeEnrollmentIds})` |
| Revocation guard                     | `excludeEnrollmentIds`                                                     |
| Authenticity of responder            | `EnvelopeSigning` (APKAM-signed envelopes)                                 |
| Idempotent store / dedup             | `SecretStore.putIfNewer(Secret)`                                           |
| Delivery stream                      | `receivedSecrets`                                                          |

The spike substrate keys the recipient by a per-client `clientId`; WP-SS re-keys it to the
per-APKAM `kpid` (`pq-secret-push.md` §3/§7) — the per-client → per-APKAM migration is the
planned end state, not the spike's current shape. The prototyped
`requestSecretsFromNamespace` requests by *namespace*; the generalisation — request **by
name** (a specific named secret) — is a small extension that lands with WP-SS.

### Details the primitive must pin down

- **Transport = `put` + sync, plus an optional wake-up notify.** Request and response are the
  *same* targeted envelope key — `<msgId>.<kpid>.__ssenv.<ns>@<owner>`, a
  self key, `shouldEncrypt=false` (already sealed) — written with `atClient.put`. Delivery is the
  **sync** service (a sync-progress listener + a periodic local sweep surface arrivals on
  `receivedSecrets`), so it is offline-tolerant by construction. **Some clients don't sync** — so
  the writer *also* sends an **optional wake-up `notify`** (default on) for that key; a sync-less
  recipient wakes on its notification monitor and `get`s the key (`useRemoteAtServer`). This
  applies to *both* the request (to each discovered peer) and the response (to the requester).
  Ideally the atServer auto-emits the notify on a `put` to `__ssenv` keys (a future server
  enhancement); until then the client sends it.
- **Responder authorisation = namespace authorisation.** A peer serves a namespaced
  secret to requester `R` only if `R`'s enrollment is authorised for that
  **namespace** (a `app_1.my_apps`-scoped enrollment must not be handed the `app_2.my_apps` key) — the
  same scope the atServer's APKAM already enforces, so the policy is just "does `R`'s
  enrollment cover this namespace." The authoritative source is the server-sourced
  `enroll:listfornamespace` verb (`pq-secret-push.md` §2/§5), not a client self-claim, and
  delivery is additionally enforced by the namespace gate on the `__ssenv.<ns>` key (the
  seal is the confidentiality boundary; the gate is defence in depth). Never serve to an
  enrollment in `excludeEnrollmentIds` (revoked). The **root** PQ key is the exception: like the
  legacy default encryption private key (conveyed to *every* enrollment regardless of
  scope — `at_enrollment_impl.dart:154-174`), it is served to every non-revoked
  client.
- **No holder online.** The request persists on the secondary; when a holder next comes
  online it sees the pending request and answers. The requester's `waitForSecret` runs
  on a timeout + backoff.
- **Thundering herd.** With N holders, avoid N simultaneous seals: responders wait a
  small random jitter and suppress if they see the answer already delivered (or the
  requester re-broadcasts "got it"). Worst case extra seals are cheap and dedup via
  `putIfNewer`.
- **Freshness / versioning.** Secrets carry a version (e.g. an epoch or `kid`) so a
  requester can ask for "current" and a responder won't serve a superseded value;
  `putIfNewer` keeps the newest.

## 2. Why the easy conveyances don't qualify

**Self-encryption-key wrap is NOT PQ-safe — it reinherits the hole we're closing.**
Wrapping a secret under the shared `selfEncryptionKey` (AES-256, identical on every
client) and storing it server-side *looks* fine (AES-256 is PQ-safe), but the self
key's provenance is RSA-tainted:

- At APKAM enrollment the `apkamSymmetricKey` is **RSA-2048-wrapped** under the
  default encryption public key in transit
  (`at_auth/lib/src/enroll/at_enrollment_impl.dart:100-102`).
- That `apkamSymmetricKey` then AES-wraps the conveyed `selfEncryptionKey` +
  `defaultEncryptionPrivateKey` (`at_enrollment_impl.dart:154-174`).
- So a harvester who records an enrollment and later breaks RSA-2048 recovers
  `apkamSymmetricKey` → `selfEncryptionKey` → and any PQ secret wrapped under it.
  Harvest-now-decrypt-later, unclosed.

This is exactly why the primitive seals per-requester to X-Wing KeyPackages instead.

**Enrollment conveyance only reaches *future* clients.** The approving AtClient *pushes*
`pqpublickey` (and the enrollment's PQ APKAM material) to a new enrollment via the
PQ-safe enroll/approve flow (WP10) — but only *at approval*. A freshly onboarded atSign
is PQ-native and generates the key at onboarding. Existing clients are past both points —
so this doc is their **retrofit**, via the request/serve pull (§5).

## 3. Worked example — the atSign-level PQ key

The roadmap (`crypto-roadmap.md`, *Cold-start*) already posits an atSign-level PQ key as
the universal fallback a peer encapsulates the **content key (CK)** to when it has no
more-specific `nskey` (data is never encrypted directly to the root — `pq-data-encryption.md`
§4), and says every authorised bob APKAM keypair can decrypt instantly, like legacy — without
saying how the private half reaches every existing APKAM keypair. That "how" **is the §1
primitive**:

- It is the **one root-level (no-namespace) secret**, so — unlike namespaced `nskey`
  keys — it is conveyed to **every** non-revoked APKAM keypair, mirroring the legacy default
  encryption private key that every enrollment receives regardless of scope.
- The public half is published at the root as **`public:pqpublickey@alice`** (see
  *Naming*).
- The private half is the root named secret; each existing APKAM keypair requests it, the
  minter — and thereafter any holder — serves it per §1 (no namespace gate, since the
  root key is universal). Verify public/private correspondence and store. Done.

No bespoke mechanism: the PQ key rides the generic request/serve path; it differs from
every other secret only in being root-scoped rather than namespaced.

### Naming

Because this key is **root** (no namespace), its name must carry no namespace suffix.
Use **`pqpublickey`**, not `publickey.pq`: a `.pq` suffix would land it *in* a
namespace called `pq`. It mirrors the legacy `public:publickey@alice` exactly, as
`public:pqpublickey@alice`.

## 4. Bootstrap — when *no* peer holds the secret yet

The §1 primitive assumes ≥1 holder. The exception is genuine creation: the very first
PQ rollout, a brand-new namespace key, etc. Two concerns: create **exactly once**,
and — for secrets that have a **published public artifact** like `pqpublickey` —
**never overwrite** that artifact.

**Exactly-once creation via the immutable write.** The atServer's **immutable** write — a
long-standing feature (set `Metadata.immutable`), *not* a new requirement — does the work: a
write to `public:pqpublickey@alice` succeeds only if the key does not yet exist, and the key
can never be overwritten thereafter. That one primitive does all the work — no
read-before-write, no convergence dance, no orphaning:

1. **Attempt create** `public:pqpublickey@alice` (create-if-absent).
   - **Succeeded** → I am the creator: generate keypair `K` (`kid = H(pub)`), store the
     private half, seed it as the conveyable root secret `pqid:<kid>`, and serve it on
     request.
   - **Rejected (already exists)** → someone beat me: **request** the private half via
     §1, verify public/private correspondence, store. I never overwrite.

Because the immutable write is atomic, exactly one keypair is ever published and every
other client falls through deterministically to "request." The same immutable write
protects each **per-(host, keyfile) PQ APKAM public key** — each host writes its own
record once (§5). (Without a create-if-absent primitive this would need a client-side
convergence protocol — read-before-write + a confirm-read + a deterministic winner rule,
kept harmless by the readiness gate — which is exactly the complexity the immutable
feature removes.)

**Optional variant — derive, don't distribute.** Derive the keypair from a single
non-derivable PQ root seed (`HKDF(seed, "atSign-default") → X-Wing`); every holder then
computes the identical keypair, replacing private-key distribution with seed
distribution. With the immutable write already settling creation, this is now only worth
it if seed-derivation buys you something else (e.g. deriving many namespace keys from one
seed). Trade-off: a root seed has atSign-wide blast radius — fine for the atSign-level
fallback key, but do **not** derive per-namespace `nskey` keys from it (keep their
tighter per-`(atSign, namespace)` blast radius per the roadmap's nskey data path design).

## 5. Upgrading existing clients — the three scenarios

**This section is the *retrofit* of an existing atSign's existing clients** — the only
population that "upgrades." Two populations never run this flow:

| Population | Upgrades? | Gets `pqpublickey` via | Gets its PQ APKAM via |
|---|---|---|---|
| **Existing atSign, existing APKAM keypair / keyfile install** (this §) | yes | **pull** — `requestSecret` (§1) | mints its own (multiple APKAM keypairs per enrollment) |
| **New atSign** | no — PQ-native | generated at CRAM onboarding (first client) | generated at onboarding |
| **New enrollment** (post-PQ, after the first client) | no | **push** — the approving AtClient conveys it via the PQ-safe enroll/approve flow | set up by enroll/approve |

So the `requestSecret` pull for `pqpublickey` is fundamentally the **one-time retrofit
path**. In steady state the key arrives by onboarding (new atSign) or enroll/approve push
(new enrollment); the pull remains only as an offline/edge backstop.

Each upgrading client bootstraps **two** PQ keypairs:

- a **PQ APKAM keypair** (signing — ML-DSA) for authentication, and
- a share of the atSign-level **PQ encryption keypair** (`pqpublickey`, X-Wing, root).

The encryption keypair is created once for the atSign and conveyed (§1, §4).

**APKAM cardinality is per (host, AtKeys file), not per client — the recipient/identity unit
is the APKAM keypair (per keyfile/install), and "per (host, AtKeys file)" names the same
unit.** Many clients/processes may share one AtKeys file on one host; they share **one** minted PQ
APKAM keypair — a host-local mint-once lock serialises it (the first to upgrade mints,
writes it into the keyfile/keychain; the rest read it). The atServer allows **multiple
APKAM keypairs per enrollment**, so if the *same* AtKeys file is also in use on another
host (copying we advise against), that host mints its own single, *different* PQ APKAM
keypair. One enrollment therefore ends up with one PQ APKAM keypair **per host its keyfile
lives on**, plus the legacy RSA key. The new granularity this unlocks is **per-APKAM**,
not per-client. (The alternative — one APKAM keypair per enrollment — would force later
hosts to fetch the first host's signing private key over §1; minting-own keeps signing
keys off the conveyance path.)

**Uniform algorithm.** Every upgrading client runs the same steps; "first" vs
"subsequent" is decided by the immutable create at step 7, not known in advance:

1. Authenticate on the existing connection (legacy PKAM/APKAM, RSA).
2. **Mint-once per host/keyfile:** if the AtKeys file already carries a PQ APKAM keypair,
   use it; else (host-local lock) mint one and write it into the keyfile/keychain. Deliver
   the public half to the server — an immutable per-(host, keyfile) record.
3. Verify it can now APKAM-authenticate with the PQ keys. *(atServer enhancement — §8.)*
4. **Delete the legacy RSA APKAM public key** for this enrollment from the atServer — only
   *after* step 3 confirms PQ auth works (delete-by-default; *Legacy deletion* below).
5. Save its AtKeys (incl. the PQ APKAM private key) to file / keychain.
6. Register its per-APKAM **key package** (X-Wing public) in its enrollment record
   (`<E>.<apkamId>.pqapkam.__manage@alice`) so the `enroll:listfornamespace` verb can return
   it to authorised pushers/requesters. (Not published — enrollment-internal.)
7. **Attempt create** `public:pqpublickey@alice` (immutable create-if-absent):
   - **won** → generate the keypair, store + seed the private half, serve it (§4);
   - **exists** → request the private half (§1), verify correspondence, store.
8. When the roster (the set of authorised APKAM keypairs) holds the key, the atSign
   advertises PQ readiness (once, atSign-wide).

The three scenarios differ in exactly **one** place — step 7 (`pqpublickey`):

| Activity | A · first | B · subsequent, same enrollment | C · subsequent, different enrollment |
|---|---|---|---|
| 1 · Initial auth | legacy APKAM (RSA) | legacy APKAM (shared enrollment key) | legacy APKAM (own enrollment key) |
| 2 · PQ APKAM keypair | mint once / host+keyfile | mint once / host+keyfile | mint once / host+keyfile |
| 2 · Publish APKAM pubkey | own record, immutable | own record, immutable | own record, immutable |
| 3 · Verify PQ APKAM auth | ✓ | ✓ | ✓ |
| 4 · Delete legacy APKAM pubkey | ✓ (first to upgrade) | ✓ idempotent | ✓ idempotent |
| 5 · Save AtKeys | ✓ | ✓ | ✓ |
| 6 · Register key package (per-APKAM enrollment record) | ✓ | ✓ | ✓ |
| 7 · `public:pqpublickey@alice` | **create** (wins) | exists → don't create | exists → don't create |
| 7 · pqpublickey private half | **generate + hold + serve** | **request + verify + store** | **request + verify + store** |
| 8 · PQ-readiness | flips it | already on | already on |

**B and C are identical for this bootstrap.** With one PQ APKAM keypair per host+keyfile,
same-vs-different-enrollment collapses here: both mint a host-local APKAM key and both
request the root `pqpublickey` (universal — served to every non-revoked APKAM keypair). The
distinction only re-emerges for **namespaced** secrets (§1): a namespace-restricted
enrollment is served only the keys for namespaces it is authorised for, so C on a
restricted enrollment receives a *subset* of the `nskey` secrets B gets. The root key is
not subject to that gate.

### Legacy APKAM deletion & what revocation means

Deleting the legacy RSA APKAM public key on upgrade is **recommended as the default** — it
is what makes per-APKAM revocation actually mean something.

- **Why delete.** The legacy RSA APKAM key is (a) quantum-vulnerable (a future forger can
  mint signatures) and (b) **shared across every copy** of the keyfile. While it remains on
  the atServer, any copy can still authenticate with it — so revoking *one* host's PQ APKAM
  key is bypassable via the shared legacy key. Per-APKAM revocation is meaningless until the
  legacy key is gone; deletion closes both the quantum hole and the bypass.
- **Order matters.** Delete only *after* PQ APKAM auth is verified (step 3 → 4), or a host
  could brick its own authentication.
- **Scope.** Delete only the legacy **APKAM** (auth) public key. **Keep** the legacy
  *encryption* keypair — it is still needed to read legacy-encrypted history; `pqpublickey`
  is additive for new data.
- **The experience/security trade-off (explicit).** If the user followed our long-standing
  advice — one keyfile, one host — deletion is invisible. If they copied the keyfile to
  other hosts, the first host to upgrade deletes the legacy key and **locks out the
  un-upgraded copies** (their legacy private key no longer matches anything on the server;
  they must re-enroll). That is arguably the correct outcome: it enforces "a given
  enrollment's private APKAM key lives in exactly one keyfile" and surfaces copying that
  shouldn't have happened. We accept harsher behaviour for the copy-violating minority to
  close the shared-key hole for everyone.
- **Softer option, if needed.** A grace period (legacy auth survives N days, then
  auto-deletes) gives stray copies time to upgrade — at the cost of leaving the bypass open
  during the window. Default to immediate delete; offer the grace period as a deployment
  knob.

**What "revocation" now means — two axes, three granularities:**

| Axis | Granularity | Mechanism |
|---|---|---|
| **Auth** | per enrollment | existing APKAM enrollment revocation (cuts every host of the enrollment) |
| **Auth** | **per-APKAM keypair** *(new)* | delete that keypair's PQ APKAM public key — works **only because** the legacy shared key was deleted |
| **Encryption** | per namespace | rotate the namespace / `pqpublickey` key **excluding** the revoked party (roadmap *rotation*, WP9) — controls *new-data* access, orthogonal to auth |

So the per-APKAM auth revocation the upgrade unlocks is *contingent* on the legacy-key
deletion above, and is a different axis from encryption-key rotation.

### Where the PQ APKAM key lives (storage & host binding)

The minted PQ APKAM **private** key must live somewhere, and the choice trades
portability, host-binding, and dev/test ergonomics. There is **no universal way to
cryptographically bind it to a host today**, so separate two goals: an
**individually-revocable per-APKAM identity** (achievable everywhere) from a
**non-exportable, host-bound key** (hardware only).

| Storage | Host binding | Dev / test | Notes |
|---|---|---|---|
| **AtKeys file** (default) | none — copyable | **clean**: the key persists with a reused keyfile, so re-runs don't re-mint | simplest; per-APKAM revocation still works for keys each host minted |
| **OS keychain** | software-local (off the portable file) | **polluting**: every fresh checkout / CI run / container mints a new key | availability varies — headless/servers may lack one |
| **TPM / Secure Enclave** | strong — non-exportable | absent in CI/containers | **no PQ (ML-DSA) support in hardware today** — not viable for this key yet |
| **Platform attestation** (App Attest / Android / TPM-remote) | strong — server admits the key only from a genuine distinct device | blocks CI/container floods (they can't attest) | platform-specific, heavy, excludes headless |

What ties a key to a host for *management / revocation* is not the storage location but a
**distinct, labelled record per APKAM keypair** (hostname / install-UUID / platform on the
published APKAM record). The label is spoofable — an administration aid, not a security
boundary — but it is what lets a revocation UI say "revoke the laptop" and makes per-APKAM
revocation usable everywhere.

**Decision (2026-06-24): store in the copyable AtKeys file section** (like the legacy APKAM) —
portable, dev/test-clean (a reused keyfile doesn't re-mint), riding the existing credential
conveyance. A copy made *after* upgrade shares the key, so revocation is **per-keyfile-key**,
not strictly per-device. Two supporting choices:
- **OS-keychain (and hardware, if it ever supports PQ) is an opt-in hardening** for single-host
  high-security deployments that want the key off the portable file and true host binding —
  **off by default**, so dev/test doesn't auto-pollute.
- **Server-side TTL / usage-based eviction of APKAM keys** (a key unused for authentication
  within N days is pruned) bounds the per-enrollment key set and self-cleans throwaway dev/test
  keys *and* abandoned hosts — independent of storage choice.

## 6. End-to-end sequence (atSign-level PQ key)

1. **Upgrade wave.** Each Alice APKAM keypair runs §5: mints its PQ APKAM keypair, registers
   its key package in its enrollment record, starts the listener. No PQ readiness advertised yet.
2. **Create once.** The first APKAM keypair to reach step 7 wins the immutable create of
   `pqpublickey`, generates the keypair, and seeds the private half as `pqid:<kid>` (§4).
3. **Convey.** Every other APKAM keypair `requestSecret(pqid:<kid>)`; a holder serves per §1
   (excluding revoked enrollments). Laggards/offline APKAM keypairs pull on next start.
4. **Verify + store** (correspondence check; the APKAM keypair's updatable keystore).
5. **Flip readiness.** Only once the roster holds the key does Alice advertise PQ
   readiness; peers encapsulate the **content key (CK)** to `public:pqpublickey@alice`
   (never application data — `pq-data-encryption.md` §4); Alice decrypts.

## 7. Edge cases

- **Offline APKAM keypair** — pulls on next startup; the request persists, a holder answers.
- **Revoked enrollment** — `excludeEnrollmentIds` keeps the secret away; to cut an APKAM
  keypair that already pulled, use the per-APKAM **revocation lever**: rotate the `nskey`
  **keypair** excluding the revoked keypair and push the successor (`pq-secret-push.md` §6.4)
  — distinct from routine CK rotation (`pq-data-encryption.md` §5.4), which is the coarse-FS
  lever, not a revocation tool.
- **New enrollment / new atSign** — never runs the §5 retrofit: a new enrollment receives
  `pqpublickey` *pushed* from the approver via enroll/approve; a new atSign generates it at
  onboarding. The §1 pull is only an offline backstop for them.
- **Two creators race** — impossible: the immutable create-if-absent admits exactly one;
  the rest fall through to "request" (§4).
- **Rotation / compromise** — two distinct levers (ADR 0002 / `pq-data-encryption.md` §5.4):
  routine forward secrecy is **CK rotation** (rotate the symmetric content key + delete the
  old `at/nskey` conveyance — O(1), no exclusion); a **compromise** triggers **nskey-keypair
  rotation** — mint a successor nskey keypair, bump `kid`/epoch, push it excluding the revoked
  APKAM keypair, supersede the old version (WP9 machinery — the expensive O(n) per-APKAM
  revocation + post-compromise-security lever, not cheap).

## 8. To verify / cross-tier notes

**atServer support.** Mint-once uses the atServer's **existing immutable write**
(`Metadata.immutable`) — already live, no change needed. The retrofit adds these **new**
atServer capabilities:
- **Multiple APKAM public keys per enrollment** — accept and store a set, authenticate
  against any of them; per-APKAM, enabling per-APKAM auth revocation.
- **PQ APKAM authentication** — verify an APKAM auth signed with a PQ signature (ML-DSA).
- **Delete a specific public key** — the legacy APKAM key on upgrade (delete-by-default,
  after PQ auth is confirmed) and a host's PQ APKAM key on revocation.
- **TTL / usage-based eviction of APKAM keys** — prune a key not used to authenticate
  within N days; bounds the per-enrollment set and self-cleans dev/test and abandoned hosts.
  Requires a **per-APKAM-key "last authenticated" timestamp** on the atServer (updated on
  each successful auth) — a small server-side data addition that eviction reads.
- **(future, optional) Auto-notify on `__ssenv` puts** — the atServer emits the wake-up
  notification itself when a secret-envelope key is written, so sync-less clients are covered
  without the sending client firing it. New functionality; until it exists the sending client
  sends the optional wake-up `notify` (default on).

**Design points to pin down:**
- **The §1 request/serve primitive is the real deliverable** — reused by the atSign-level
  PQ key, per-namespace `nskey` **private** distribution (the nskey is a KEM keypair; the
  conveyed value is its private half, not a data key), rotation, and master-seed conveyance.
  Steady-state conveyance is the **push** (`pq-secret-push.md`, the dual of this doc), with
  this pull as the offline backstop. Worth promoting in the plan from "substrate plumbing"
  to a named, spec'd primitive (`requestSecret(name)` + responder authorisation policy).
- **Responder authorisation policy** (which enrollment may receive which namespaced
  secret) needs a precise spec — it is the access-control core of the primitive.
- **Confirm WP10 enroll/approve conveys over the PQ enrollment key, not the RSA-wrapped
  `apkamSymmetricKey`** — else §2's hole reopens for future clients.

## 9. How this maps to the plan (no plan edits yet)

- Reuses **WP-SS** (per-APKAM key packages, `pqSeal` secrets, `requestSecretsFromNamespace`,
  `excludeEnrollmentIds`) — generalised to **request-by-name**, with discovery via the
  `enroll:listfornamespace` verb (not scanning published key packages) and the substrate
  re-keyed from per-client `clientId` to per-APKAM `kpid` (`pq-secret-push.md` §3/§7).
- Reuses **WP9** rotation/revocation for succession.
- Complements **WP10** (future enrollments); this is the existing-client counterpart.
- **New, not yet explicit:** (a) the generic **`requestSecret(name)`** primitive +
  responder authorisation; (b) the **per-APKAM PQ upgrade** (mint-own,
  multiple-per-enrollment) + the atServer enhancements above; and (c) the **atSign-level
  PQ key lifecycle** (immutable create + existing-client pull). Candidates for added work
  items once the approach is chosen.
