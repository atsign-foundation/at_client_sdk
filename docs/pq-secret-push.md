# PQ crypto — proactive secret push

**Status:** working planning doc (not plan-of-record). Lives in `docs/`.
**Companion to** `pq-atsign-key-distribution.md` (the **pull** primitive `requestSecret`)
— this is its **push** dual: how a holder *proactively* conveys a namespaced secret to the
enrollments authorised for it, so the secret is already on-device before a client needs it.
Push exists to make the common cases never feel slow: with secrets pre-delivered, a read in a
namespace doesn't pay a discover→request→wake→serve round-trip at the moment the user is
waiting.

**Conventions.** Notation per `pq-use-case-catalogue.md`. Each worked example gives
**Given** (state), **When** (trigger), **Steps** (protocol sequence with concrete at-keys),
**Then** (testable acceptance). "Working name" marks an at-key/verb name not yet finalised.
`aS = pq` (PQ-capable atServer) unless stated. Key names are shown **complete** — with the
`@<owner>` suffix.

**Two settled decisions shape everything below:**
- **Sharing is per-APKAM, not per-client.** The recipient unit is an **APKAM keypair** (one
  per keyfile/install — see `pq-atsign-key-distribution.md`, *APKAM cardinality*), not an
  individual client process. Each APKAM keypair is paired with **one X-Wing key package** (the
  encryption key a sender seals to). One enrollment may hold **several** APKAM keypairs, hence
  several key packages. A secret sealed to an APKAM keypair's key package is openable by every
  client sharing that keyfile — so per-client sealing would only be redundant.
- **Discovery is a gated atServer verb, and key packages are enrollment state.** A new verb
  **`enroll:listfornamespace:<ns>`** (working name) returns the enrollments authorised for
  `<ns>` *and each one's per-APKAM key packages*, gated on the requester holding ≥`r` on `<ns>`.
  Key packages are carried in the per-APKAM enrollment record — **never public**, never a
  client-published at-key.

## Table of contents

- [1. The shift from pull to push](#1-the-shift-from-pull-to-push)
- [2. Discovery — the namespace-to-enrollment verb](#2-discovery--the-namespace-to-enrollment-verb)
- [3. Recipient granularity — APKAM-level, not per-client](#3-recipient-granularity--apkam-level-not-per-client)
- [4. Key shapes](#4-key-shapes)
- [5. Authorization & safety](#5-authorization--safety)
- [6. Worked examples (given / when / then)](#6-worked-examples-given--when--then)
  - [6.1 An enrollment registers its key packages](#61-an-enrollment-registers-its-key-packages)
  - [6.2 Newly minted nskey pushed to all members (req 1)](#62-newly-minted-nskey-pushed-to-all-members-req-1)
  - [6.3 Approval conveys nskey secrets for granted namespaces (req 2)](#63-approval-conveys-nskey-secrets-for-granted-namespaces-req-2)
  - [6.4 Rotation pushes the successor, excluding the revoked (req 3)](#64-rotation-pushes-the-successor-excluding-the-revoked-req-3)
  - [6.5 A read-only enrollment receives by push](#65-a-read-only-enrollment-receives-by-push)
- [7. Mapping to the substrate](#7-mapping-to-the-substrate)
- [8. Open atServer decisions](#8-open-atserver-decisions)
- [9. D1 secret inventory — what's shared and at what granularity](#9-d1-secret-inventory--whats-shared-and-at-what-granularity)
- [10. Relationship to the plan](#10-relationship-to-the-plan)

# 1. The shift from pull to push

`pq-atsign-key-distribution.md` builds a **pull** primitive: a client that *needs* a named
secret discovers the namespace's clients, fans out a sealed request, and a holder serves it.
The three goals here are the **push** dual — a holder converges the roster proactively:

1. **Newly-minted `nskey` secrets are pushed to all enrollments with `r` or `rw` on that
   namespace** — no one has to ask.
2. **Approval conveys all `nskey` secrets** for the namespaces a new enrollment was granted.
3. **The push generalises to every namespace-bound shared secret** (rotated nskey keypairs, app
   secrets, and — once it lands — the `at/pqmls` (D2) provider's keying material), not just `nskey`.

Push and pull are complementary, and pull remains the **correctness backstop** — a push
failure is never fatal because pull still serves an offline/missed client later. They compose
because arrival is idempotent (`SecretStore.putIfNewer` keeps the newest). The reason to add
push on top of a complete pull is **latency and availability**: clients are frequently
offline, so a pull at point-of-need can stall on "no holder online right now," and even a
successful pull adds a round-trip exactly when the user is waiting on a read. Push moves that
work to when holders *are* online, so the secret is already local.

For push to deliver on "never slow," it must be **complete** — every authorised enrollment,
read-only included, or the missed ones silently fall back to the slow pull. That completeness
is what the verb in section [2](#2-discovery--the-namespace-to-enrollment-verb) guarantees.

# 2. Discovery — the namespace-to-enrollment verb

A pusher needs two facts: **who** is authorised for the namespace, and **what key** to seal to
for each. One gated verb returns both:

> **`enroll:listfornamespace:<ns>`** (working name) — returns every enrollment authorised for
> `<ns>`, with its access level and its **per-APKAM key packages**. **Gated:** the requester
> must hold ≥`r` on `<ns>`.

- **Definitive, server-sourced.** The authorisation comes from the atServer's enrollment
  records — not a client self-claim — so the member list is complete and trustworthy,
  including **read-only** enrollments (which cannot self-advertise into a namespace they can't
  write).
- **Self-contained (decision B).** The X-Wing key package travels in the per-APKAM enrollment
  record alongside the PQ APKAM (ML-DSA) public key; the verb returns it. So one gated call
  yields *authorisation + every encapsulation key* — no separate key-package fetch, no
  public records, no cross-enrollment read rule.
- **Multiple key packages per enrollment.** An enrollment with two APKAM keypairs (e.g. a
  keyfile on two installs) has two key packages; the verb returns both, and the pusher seals
  once per key package (section [3](#3-recipient-granularity--apkam-level-not-per-client)).
- **Gate scope.** ≥`r` is the right bar: any pusher (the `rw` minter, a rotator) clears it, and
  a read-only co-member learning the roster of a namespace it already belongs to is not a leak.

This replaces every discovery workaround considered earlier — the hidden-public canonical key
package, the `rw`-only `__sskbns.<namespace>` self-advertise copies, and the per-enrollment
"inbox". None are needed: the verb is the single discovery path, and delivery rides the
existing namespace-gated channel.

**Approval (req 2) doesn't even need the verb:** the approver already holds the new
enrollment's id and its granted namespaces, and it reads the new enrollment's key packages
from the same per-APKAM records (it has the enrollment in hand). The verb is for the
*enumerate-all-members* cases — mint (req 1) and rotation (req 3).

# 3. Recipient granularity — APKAM-level, not per-client

The unit a secret is sealed to is an **APKAM keypair**, identified by its key package id
(`kpid` = the kid of its X-Wing public key). Rationale:

- **One keyfile, one recipient.** All client processes that share a keyfile/keychain share
  that keyfile's APKAM keypair *and* its X-Wing key package private half. Sealing once per
  key package reaches all of them; per-client sealing would duplicate work for processes that
  already share storage.
- **It matches the revocation granularity.** Revocation in the retrofit design is per
  enrollment or per APKAM keypair (`pq-atsign-key-distribution.md`, *what revocation means*) —
  never per process — so the recipient unit is the APKAM keypair.
- **The key package is paired with the APKAM keypair.** Generated locally with each APKAM
  keypair at enrolment/upgrade (its **private half never leaves the keyfile**), registered in
  the per-APKAM enrollment record next to the ML-DSA APKAM public key. "Every APKAM keypair is
  accompanied by a key package" is literal.

**Nothing in D1 forces per-client sealing** (the full inventory is in section
[9](#9-d1-secret-inventory--whats-shared-and-at-what-granularity)). Every shared D1 secret
decrypts data scoped at atSign / namespace / group level (not per process); the only genuinely
per-APKAM artefacts (the PQ APKAM signing keypair, the X-Wing key package private half) are
**minted locally and never shared**. So there is a clean split: *shared ⇒ ≥ namespace scope ⇒
APKAM-level delivery is correct; per-APKAM ⇒ locally generated ⇒ never on the wire.*

This is a shift from the spike substrate, which keys by a per-client `clientId`. The migration
is: generate the X-Wing keypair with each APKAM keypair, register its public half in the
per-APKAM enrollment record, and address envelopes by `kpid` rather than `clientId`.

# 4. Key shapes

Concrete, with `@alice` as owner. Enrollments `E1/E2/E3/E4`; APKAM keypairs `K1…K4`; key
packages `KP1…KP4` with ids `kp1…kp4`; namespace `app_1.my_apps` (reads right-to-left,
DNS-style). Working names marked.

| Purpose | At-key / record | Kind | Notes |
|---|---|---|---|
| **Per-APKAM enrollment record** *(working)* | `<E>.<apkamId>.pqapkam.__manage@alice` | enrollment state (immutable per APKAM keypair) | carries the ML-DSA APKAM pubkey **and** the X-Wing **key package**; one per APKAM keypair |
| **Namespace→enrollment query** *(working)* | verb `enroll:listfornamespace:app_1.my_apps` | gated read (≥`r`) | returns `[{enrollmentId, access, apkam:[{apkamId, apkamPubKey, keyPackage}]}]` |
| **Delivery envelope** | `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice` | self, `shouldEncrypt=false` | sealed (`pqSeal`) to key package `<kpid>`; the atServer **gates delivery by namespace** |
| **Self nskey — private (the secret)** | `nskey.app_1.my_apps@alice` (self nskey, **not** published) | self | held by authorised APKAM keypairs; the value pushed. X-Wing KEM private — Alice encapsulates **her own** content keys (CKs) to the self nskey's public half |
| **Public nskey — public (encapsulate-to)** | `public:nskey.app_1.my_apps@alice` | public | world-readable; **external senders** encapsulate CKs to it. Its private half is also held by authorised APKAM keypairs and pushed the same way |
| **Root PQ key — public** | `public:pqpublickey@alice` | public (immutable) | atSign-level fallback; private half conveyed by **pull** (root, no namespace) + **push** at approval; onboarding generates it locally |
| **Per-enrollment signing key** (existing) | `public:_apsk.<E>.a.__e@alice` | public (single-`_`, unscannable) | verify an enrollment's envelope signatures |

The delivery envelope is the substrate's existing channel, only re-addressed by `kpid`
(per-APKAM) instead of `clientId` (per-process). No inbox, no ack, no namespace-copy.

# 5. Authorization & safety

**Discovery is authoritative; the channel enforces.** The verb returns exactly the authorised
members, so over-delivery isn't a concern. And delivery is itself the enforcement: the envelope
`<msgId>.<kpid>.__ssenv.<N>@alice` is a self key *in namespace `N`*, which the atServer delivers
only to enrollments with ≥`r` on `N`. So even if a pusher sealed to the wrong key package, the
server would not deliver it — **discovery/sealing mistakes cannot leak.** Read-only enrollments
*receive* fine here: they hold `r` on `N`, so they can read the envelope.

**The seal is the confidentiality boundary.** The envelope value is raw `pqSeal` bytes
(`shouldEncrypt=false`) sealed to one key package; the namespace gate only governs who may fetch
the ciphertext, which is useless without that keyfile's X-Wing private half. Gate = defence in
depth; seal = boundary.

**Sender authenticity:** the envelope is APKAM-signed and verified before decrypt (substrate
`_consume`), proving a genuine Alice client wrote it. For a keypair secret (`nskey`,
`pqpublickey`) the receiver also checks public/private correspondence against the published
public half — so a wrong key can't be injected.

**Cross-tier property to state in commits:** push delivery is safe *only because* the atServer
refuses to deliver an `…__ssenv.<N>` key to an enrollment lacking `r` on `N`, and the verb's
member list is authoritative. Both are atServer guarantees the client relies on.

**Read-only cleanup wrinkle (unchanged):** a read-only recipient can read but not delete the
consumed envelope (no write in `N`), so it lingers to `envelopeTtl`; re-consumption is
idempotent (`putIfNewer`). Acceptable; TTL is the cleanup.

# 6. Worked examples (given / when / then)

Cast: `@alice`, `aS = pq`. `E1` (rw on `app_1.my_apps`, APKAM keypair `K1`, key package
`KP1/kp1`), `E2` (rw, `K2`, `KP2/kp2`), `E3` (**read-only `r`**, `K3`, `KP3/kp3`). Each
registered its per-APKAM record; each runs the substrate listener.

## 6.1 An enrollment registers its key packages

- **Given:** `E3` is read-only (`r`) on `app_1.my_apps`; it can write nothing in that namespace.
- **When:** `E3` completes PQ enrolment/upgrade.
- **Steps:**
  1. `E3` mints its **PQ APKAM** keypair `K3` (ML-DSA) **and** its **X-Wing key package** `KP3`;
     both private halves stay in `E3`'s keyfile.
  2. `E3` registers the per-APKAM record `E3.K3.pqapkam.__manage@alice` carrying the APKAM
     pubkey and `KP3` (immutable per APKAM keypair). This is enrolment state — no
     application-namespace write is involved, so `E3`'s read-only status is irrelevant to it.
- **Then:**
  - `E3`'s key package is registered even though `E3` can't write any application namespace.
  - `enroll:listfornamespace:app_1.my_apps` (called by any ≥`r` member) returns `E3` with
    `KP3` among the results.
  - Nothing is public; `KP3` is enrollment-internal.

## 6.2 Newly minted nskey pushed to all members (req 1)

- **Given:** no `nskey` exists for `app_1.my_apps`; `E1` is about to write the first self datum
  in it. Members: `E1` (rw), `E2` (rw), `E3` (r), all with registered key packages.
- **When:** `E1` mints `nskey.app_1.my_apps@alice`.
- **Steps:**
  1. `E1` **mints the namespace's nskeys**, establishing **both** the **self nskey** (the
     unpublished `nskey.app_1.my_apps@alice`, to which Alice encapsulates her own CKs) and the
     **public nskey** (immutable-creates `public:nskey.app_1.my_apps@alice`, to which external
     senders encapsulate). Each is an X-Wing keypair; `E1` holds both privates and seeds each as
     `Secret(namespace: app_1.my_apps, name: nskey:<kid>, value: <private>)`. The push conveys
     these nskey **privates**; the symmetric content keys (CKs) the nskeys wrap are cut and
     conveyed separately as `at/nskey` records on ordinary sync (see `pq-data-encryption.md`).
  2. **Discover:** `enroll:listfornamespace:app_1.my_apps` → `[{E1,rw,[KP1]}, {E2,rw,[KP2]},
     {E3,r,[KP3]}]`. `E1` drops itself.
  3. **Seal + deliver**, once per key package: `pqSeal` the secret to `KP2`, `put`
     `<msgId>.kp2.__ssenv.app_1.my_apps@alice`; likewise `<msgId>.kp3.__ssenv.app_1.my_apps@alice`
     for `KP3`. Fire the wake-up notify.
- **Then:**
  - `E2` and `E3` receive, verify (APKAM signature + public/private correspondence against
    `public:nskey.app_1.my_apps@alice`), and `putIfNewer` the private half.
  - **Read-only `E3` receives it** — it holds `r` on the namespace, so the atServer delivers
    the envelope. The first read of `app_1.my_apps` data on `E3` is instant (key already local).
  - An APKAM keypair that was offline during the push still gets it via the **pull** backstop.
  - If `E2` also had a second APKAM keypair `K2'` (a second keyfile) with key package `KP2'`,
    the verb returns both and step 3 seals to each — APKAM-level, one seal per APKAM keypair.

## 6.3 Approval conveys nskey secrets for granted namespaces (req 2)

- **Given:** `E1` is approving new enrollment **`E4`** (APKAM keypair `K4`, key package `KP4`)
  requesting `[app_1.my_apps (rw), app_2.my_apps (r)]`. `nskey` secrets exist for both
  namespaces; `E1` holds their private halves.
- **When:** `E1` approves `E4`.
- **Steps:**
  1. Approve `E4` over the **PQ enrollment key** (WP10), granting
     `{app_1.my_apps: rw, app_2.my_apps: r}`. `E4` registers its per-APKAM record with `KP4`.
  2. `E1` (holding `approvedNamespaces` and `E4`'s key packages from the records it just
     handled) seals each held secret whose namespace `E4` was granted, to `KP4`, and delivers:
     `nskey.app_1.my_apps@alice` on `<m1>.kp4.__ssenv.app_1.my_apps@alice` **and**
     `nskey.app_2.my_apps@alice` on `<m2>.kp4.__ssenv.app_2.my_apps@alice`.
- **Then:**
  - `E4` receives exactly the `nskey` secrets for the two namespaces it was granted — nothing
    else.
  - `r`-only on `app_2.my_apps` suffices to **receive** that nskey (read access is the bar to
    receive a namespace secret).
  - No verb call is needed — the approver already had the target and the grant. This is
    `shareAllSecretsWithEnrollment(E4, approvedNamespaces)`, re-keyed to APKAM-level.

## 6.4 Rotation pushes the successor, excluding the revoked (req 3)

- **Given:** `app_1.my_apps`'s `nskey` is compromised on `E3`; `E1` rotates the nskey **keypair**
  (the per-APKAM revocation lever — distinct from routine CK rotation). The mechanism is identical
  for *any* namespaced secret (an app secret, and — once it lands — the `at/pqmls` (D2) provider's
  keying material).
- **When:** `E1` mints the successor `nskey.app_1.my_apps@alice` (new `kid`).
- **Steps:**
  1. Mint the successor; supersede `public:nskey.app_1.my_apps@alice`.
  2. **Discover + exclude:** `enroll:listfornamespace:app_1.my_apps`, then drop `E3` (revoked)
     and self `E1` → `{E2,[KP2]}`.
  3. Seal the successor to `KP2`, deliver `<msgId>.kp2.__ssenv.app_1.my_apps@alice`.
- **Then:**
  - `E2` holds the new key; `E3` does not — excluded at discovery **and** unable to read the
    envelope even if included.
  - The generic push call — *"seal this `Secret` to every authorised member of its namespace,
    minus excludes"* — is byte-for-byte the same as [6.2](#62-newly-minted-nskey-pushed-to-all-members-req-1);
    only the `Secret` and exclude-set differ. That sameness *is* requirement 3.

## 6.5 A read-only enrollment receives by push

This isolates the property that made read-only the hard case, now resolved by the verb +
APKAM-level delivery.

- **Given:** `E3` is read-only on `app_1.my_apps` and was offline during the original mint
  push ([6.2](#62-newly-minted-nskey-pushed-to-all-members-req-1)); it now comes online.
- **When:** `E3` comes online; a holder (`E1`) is running.
- **Steps:**
  1. `E3` **cannot** initiate a pull — a request is a write of `…__ssenv.<N>` *in* `app_1.my_apps`,
     which read-only access forbids. So `E3` waits to be pushed to.
  2. On its periodic push (or on the next mint/rotation), `E1` calls the verb, sees `E3` (with
     `KP3`) is still an authorised member, and re-delivers the current `nskey` to
     `<msgId>.kp3.__ssenv.app_1.my_apps@alice`.
  3. `E3` reads, verifies, `putIfNewer`.
- **Then:**
  - `E3` ends up with the key **without ever writing the namespace** — push is its only route,
    and the verb guarantees it is never forgotten (so it doesn't go stale across rotations).
  - This is why "pull is sufficient for read-only" is **false** and push is required for them:
    read-only can't write a pull request, but it *can* read a pushed envelope.

# 7. Mapping to the substrate

| Need | Status | Where |
|---|---|---|
| Per-recipient seal / open | **built** | `pqSeal`/`pqOpen` (`SecretEnvelope`, `pairwise_secret_sharing.dart`) |
| Serve one secret to one recipient | **built** | `shareSecretWith(keyPackage, Secret)` — re-key recipient to `kpid` |
| Approval conveyance (req 2) | **built** | `shareAllSecretsWithEnrollment(E, approvedNamespaces)` — wire into approve; re-key to APKAM-level |
| Namespace-gated delivery + wake-up | **built** | `…__ssenv.<namespace>` channel + wake-up notify |
| Idempotent merge (push ∥ pull) | **built** | `SecretStore.putIfNewer` |
| Revocation guard | **built** | `excludeEnrollmentIds` on discovery/serve |
| **Push to all members (req 1, 3)** | **new** | `pushSecretToNamespaceMembers(Secret, {exclude})` = verb → seal per key package |
| **`enroll:listfornamespace:<ns>` verb** | **new (atServer)** | gated read; returns enrollments + per-APKAM key packages |
| **Key package in per-APKAM enrollment record** | **new (atServer + client)** | register X-Wing key package with the PQ APKAM record; drop the public/at-key key package |
| **APKAM-level addressing** | **new (client)** | address envelopes by `kpid` (per-APKAM), not `clientId`; one X-Wing keypair per APKAM keypair |

Requirements 1 and 3 collapse to one push method over the verb; requirement 2 is an existing
method wired into approve. The structural new work is the **verb + key-package-in-enrollment-record**
(atServer) and the **per-client → per-APKAM re-keying** (client).

# 8. Open atServer decisions

1. **Verb response shape** — confirm `enroll:listfornamespace:<ns>` returns, per enrollment:
   `enrollmentId`, `access` (`r`/`rw`), and `apkam: [{apkamId, apkamPubKey, keyPackage}]`
   (multiple per enrollment). Access level is returned even though delivery treats `r` and `rw`
   identically — it lets push apply policy and is near-free.
2. **Key package in the per-APKAM record** — confirm the X-Wing key package is registered with
   the PQ APKAM record (immutable per APKAM keypair) and updatable on key-package rotation.
3. **Verb gate** — ≥`r` on `<ns>` (a co-member may enumerate the roster). Confirm acceptable.
4. **Eviction interplay** — the per-APKAM record (APKAM key + key package) is subject to the
   TTL/usage eviction already planned for APKAM keys (`pq-atsign-key-distribution.md`,
   section 8), so abandoned APKAM keypairs drop out of the verb's results automatically.
5. **Root key stays pull** — `pqpublickey` is root (no namespace), so there is no
   `enroll:listfornamespace` for it; it keeps the pull/onboarding/approval paths of the
   distribution doc. Push here is namespaced only.

# 9. D1 secret inventory — what's shared and at what granularity

Every secret D1 conveys, why, how often, and the granularity it is shared at. This is the
evidence for section [3](#3-recipient-granularity--apkam-level-not-per-client)'s claim that
APKAM-level delivery is correct for all of D1.

**Shared secrets** (sealed with `pqSeal` and sent between APKAM keypairs):

| Secret | Purpose | Holder scope | Frequency | Conveyance |
|---|---|---|---|---|
| `pqpublickey` **private** half | atSign-level fallback encryption key — decrypt when no `nskey` applies; replaces the legacy default encryption private key | per **atSign** (root, no namespace) | once per atSign; rare rotation | **pull** (retrofit) + **push** at approval; onboarding generates it locally |
| `nskey.<ns>` **private** half (self + public nskey) | namespace KEM private — **decapsulates** the content keys (CKs) that decrypt self data + inbound shares in `<ns>` (it never decrypts data directly) | per **(atSign, namespace)** | once on first use of `<ns>`; occasional rotation | **push** to ≥`r` members on mint/rotate (req 1/3) + **pull** backstop + approval (req 2) |
| Symmetric **content key (CK)** rotation | D1's coarse forward-secrecy lever in the single-tier nskey data path (`at/nskey` + `at/symmetric/AES/GCM`) — rotate the CK + delete the old `at/nskey` conveyance | per **(atSign, namespace)**, per CK epoch | **highest** — per CK-rotation cadence | conveyed as an `at/nskey` record on ordinary sync (see `pq-data-encryption.md`), **not** via the substrate push |
| `apkamSymmetricKey` | wraps the enrolment response so the approver can convey material | per **enrollment**, transient | once per enrolment | enrolling APKAM keypair → approver, encapsulated to `pqpublickey` (PQ-safe) |
| *(retrofit only)* legacy `defaultEncryptionPrivateKey` (RSA) + `selfEncryptionKey` | read **legacy-encrypted history** (not new data) | per **atSign** | once per enrolment; being phased out | existing enrolment conveyance |
| *(conditional)* root PQ **seed** | only if the "derive-don't-distribute" variant (`pq-atsign-key-distribution.md` section 4) is adopted | per **atSign** (wide blast radius) | once | same path as `pqpublickey` private; **not** used to derive per-namespace keys |

**Never shared — minted locally per APKAM keypair, never on the wire:**

- **PQ APKAM signing keypair** (ML-DSA) — minting-own is deliberate, to keep signing keys off
  the conveyance path.
- **X-Wing key package private half** — the recipient/leaf key; only its *public* half is
  registered (in the per-APKAM enrollment record), the private half stays in the keyfile.

**Which must be per-client? None.** Every *shared* D1 secret decrypts data scoped at atSign /
namespace / group level — none binds to a single process, so APKAM-level delivery is the
correct granularity, not a compromise. The only key that is inherently **unique per
recipient** is the **key package / leaf keypair itself** — which is exactly the one we *don't*
share, and whose granularity is set to per-APKAM. So even the strongest per-identity case (a
D2 (`at/pqmls`) MLS-style group leaf) lands at per-APKAM: two clients sharing one keyfile
already share the APKAM keypair and trust boundary, so a per-process leaf would buy nothing.

Two caveats: the `at/pqmls` provider (D2) keying specifics (rotation cadence, exactly what is
sealed per member) ride on the ratcheted/TreeKEM group design (WP-GP), a separate D2 piece — if it
ends up MLS-strict the per-member *leaf* is still per-APKAM, but re-check when that firms up.
And `apkamSymmetricKey` is the one per-*enrollment* item, but it is transient
enrolment-handshake material, not a steady-state shared secret.

# 10. Relationship to the plan

- **Extends WP-SS** (the secret-sharing substrate): adds the push method and re-keys the
  recipient unit from client to APKAM keypair.
- **Dual of `pq-atsign-key-distribution.md`** (pull): push is the steady-state convergence that
  keeps reads fast; pull is the offline/edge backstop and the correctness guarantee.
- **Feeds WP10** (enroll/approve): requirement 2 is the approve-time conveyance, prototyped as
  `shareAllSecretsWithEnrollment`.
- **Reuses WP9** (rotation/revocation): requirement 3's push + `excludeEnrollmentIds` is the
  redistribute-on-rotation path.
- **New atServer capability** (beyond the PQ-APKAM set in `pq-atsign-key-distribution.md`,
  section 8): the **`enroll:listfornamespace:<ns>`** verb and the **X-Wing key package in the
  per-APKAM enrollment record**.
