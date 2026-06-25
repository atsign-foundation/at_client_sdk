# PQ crypto — use-case catalogue (given / when / then burn-down)

**Status:** working planning doc (not plan-of-record). Lives in `docs/`.
**Purpose:** a comprehensive, ordered target of use cases and their acceptance
("then"), so dev can be burned down against a known list. Build order is
**Part A — the new world** (greenfield, PQ-native) **before Part B — retrofit/upgrade**
(mixtures of pre-PQ and post-PQ). First-cut "then" rows are starting points to refine.

## Table of contents

- [Notation & state model](#notation--state-model)
- [Part A — The new world (PQ-native, PQ-capable atServer)](#part-a--the-new-world-pq-native-pq-capable-atserver)
  - [A1 · Onboard a new atSign](#a1--onboard-a-new-atsign)
  - [A2 · Enrollments (a new APKAM keypair joins)](#a2--enrollments-a-new-apkam-keypair-joins)
  - [A3 · E2EE within one atSign (self data)](#a3--e2ee-within-one-atsign-self-data)
  - [A4 · E2EE across atSigns (shared data)](#a4--e2ee-across-atsigns-shared-data)
  - [A5 · Rotation & revocation (new world)](#a5--rotation--revocation-new-world)
- [Part B — Retrofit / upgrade (mixtures of pre-PQ and post-PQ)](#part-b--retrofit--upgrade-mixtures-of-pre-pq-and-post-pq)
  - [B0 · Prerequisite — atServer upgrade](#b0--prerequisite--atserver-upgrade)
  - [B1 · Upgrade an existing (pre-PQ) atSign — the three scenarios](#b1--upgrade-an-existing-pre-pq-atsign--the-three-scenarios)
  - [B2 · Legacy APKAM deletion consequences](#b2--legacy-apkam-deletion-consequences)
  - [B3 · Mixed-PQ within one atSign (some APKAM keypairs upgraded)](#b3--mixed-pq-within-one-atsign-some-apkam-keypairs-upgraded)
  - [B4 · Mixed-PQ across atSigns](#b4--mixed-pq-across-atsigns)
  - [B5 · Retrofit edge cases](#b5--retrofit-edge-cases)
- [Decisions](#decisions)
- [Coverage map (build-order checklist)](#coverage-map-build-order-checklist)

## Notation & state model

**Actors.** `@alice`, `@bob` are atSigns. `alice1`, `alice2`, `alice3` are *APKAM keypairs*
of `@alice` — the recipient/identity unit is the **APKAM keypair** (one per keyfile/install),
not a running client process: every process that shares a keyfile/keychain shares that one
APKAM keypair. One enrollment may hold **several** APKAM keypairs. Likewise `bob1`, `bob2`.
`aliceS` / `bobS` are the atServers. (Per `pq-secret-push.md` section
[3](pq-secret-push.md#3-recipient-granularity--apkam-level-not-per-client) and ADR 0002:
sharing, revocation, eviction and readiness all key on the APKAM keypair.)

**Per-APKAM state** — the row unit is an APKAM keypair (per keyfile/install), not a client
process:

| Col | Meaning |
|---|---|
| `enr` | enrollment the APKAM keypair is on (`E1`, `E2`, …) |
| `APKAM` | auth keypair held: `rsa` (legacy) · `pq` (ML-DSA) · `both` |
| `pqpk⁻¹` | holds the atSign-level `pqpublickey` **private** half? |
| `nskey⁻¹` | holds **both** nskey **privates** for the namespace — the **self-nskey** private and the **public-nskey** private, per namespace (an `@alice` APKAM keypair holds both for `<ns>@alice`); these **decapsulate content keys (CKs)**, they do not decrypt application data — see *Namespace key shapes* |
| `KP` | its X-Wing **key package** (`kid` = `kpid`, for receiving sealed secrets) is registered in the per-APKAM enrollment record? (one key package per APKAM keypair, never published) |

**Per-atSign / server state:**

| Col | Meaning |
|---|---|
| atSign | `legacy` · `pq-native` · `mixed` |
| `aS` | atServer: `pq` (new verbs) · `legacy` |
| `publickey` | legacy RSA encryption pubkey published? |
| `pqpublickey` | atSign-level PQ encryption pubkey published (immutable)? |
| `nskey.ns` | namespace PQ pubkey published for namespace `ns`? |
| `ready` | PQ-readiness marker, **per (atSign, namespace)** (+ an atSign-level marker for the root `pqpublickey`): `n-r` (not ready) · `ready` |

**Namespace key shapes.** A namespace keypair (`nskey`) for namespace `app_1.my_apps`
(key name `nskey`, namespace `app_1.my_apps` — namespaces read right-to-left, DNS-style, so
app `app_1` under org `my_apps`) has **two** at-key shapes per atSign (shown for both) — keep
them distinct:

| Shape | Meaning |
|---|---|
| `nskey.app_1.my_apps@alice` (self nskey) | @alice's **self nskey** — **not published**; alice's own authorised APKAM keypairs hold its **private** half and encapsulate her **own** CKs to it; the private **decapsulates** those CKs (it does not decrypt data) |
| `public:nskey.app_1.my_apps@alice` | the **public nskey**'s public half, **published world-readable** — **external senders** (a peer) encapsulate CKs to it to send to @alice; @alice's own self data uses the **self nskey**, not this one |
| `nskey.app_1.my_apps@bob` (self nskey) | @bob's **self nskey** — not published; bob's authorised APKAM keypairs hold its private half and encapsulate bob's own CKs to it |
| `public:nskey.app_1.my_apps@bob` | @bob's **published public** half — external senders (incl. @alice) encapsulate CKs to it to send to @bob |

There are **two** nskeys per `(atSign, namespace)`: the **self nskey** (not published; the owner
encapsulates her own CKs to it) and the **public nskey** (published; external senders encapsulate
CKs to it). Both nskey privates are held only by the owning atSign's own authorised APKAM
keypairs (the `nskey⁻¹` column). Both nskeys are asymmetric KEMs (X-Wing) that only ever **wrap symmetric content keys** —
they never encrypt application data directly.

**atServer PQ capabilities** (Part A and B both assume `aS = pq` unless stated): the
**existing** immutable write (`Metadata.immutable`) for mint-once, plus the **new** verbs —
multiple APKAM keys per enrollment + auth-against-any · PQ (ML-DSA) APKAM auth · delete a
specific pubkey · TTL/usage eviction of APKAM keys · **`enroll:listfornamespace:<ns>`** (the
gated discovery verb that returns the enrollments authorised for `<ns>` and each one's
per-APKAM key packages — the steady-state push primitive, gated on the requester holding
≥`r` on `<ns>`; see `pq-secret-push.md` section
[2](pq-secret-push.md#2-discovery--the-namespace-to-enrollment-verb)).

---

# Part A — The new world (PQ-native, PQ-capable atServer)

## A1 · Onboard a new atSign

**UC-A1.1 — First-APKAM-keypair CRAM onboard is PQ-native**
- **Given:** `@alice` unactivated; `aliceS = pq`; no keys exist.
- **When:** `alice1` runs CRAM onboarding.
- **Then:** `alice1.APKAM = pq` and it authenticates via PQ APKAM; `public:pqpublickey@alice`
  is published (immutable) and `alice1.pqpk⁻¹ = ✓`; `alice1.KP = ✓`; readiness can be
  `ready` (no legacy APKAM keypairs exist). **Legacy interop is a config flag (default off):** by
  default a PQ-native atSign is PQ-only — no RSA `public:publickey@alice`; enable the flag to
  publish it for legacy-peer inbound (see UC-B4.2).

| APKAM | enr | APKAM-kind | pqpk⁻¹ | nskey⁻¹ | KP |
|---|---|---|---|---|---|
| alice1 | E1 | pq | ✓ | — | ✓ |

## A2 · Enrollments (a new APKAM keypair joins)

**UC-A2.1 — New enrollment, approved by an online APKAM keypair (PQ-safe enroll/approve)**
- **Given:** `@alice` pq-native; `pqpublickey` published; `alice1` enrolled (E1) & online.
- **When:** `alice2` requests enrollment (E2); `alice1` approves.
- **Then:** `alice2.APKAM = pq` (its own); `alice2.pqpk⁻¹ = ✓` — the approver conveys the
  nskey/`pqpublickey` privates **per-APKAM** by sealing (`pqSeal`) to `alice2`'s X-Wing key
  package and writing a `<msgId>.<kpid>.__ssenv.<ns>@alice` delivery envelope
  (`shareAllSecretsWithEnrollment`, `pq-secret-push.md` section
  [6.3](pq-secret-push.md#63-approval-conveys-nskey-secrets-for-granted-namespaces-req-2));
  *not* RSA-wrapped. `alice2.KP = ✓`; `alice2` can authenticate PQ and decrypt `@alice`'s PQ
  self data within its authorised namespaces.

**UC-A2.2 — Second host using the *same* keyfile (copied keyfile, E1)**
- **Given:** `@alice` pq-native; `alice1` on E1; a second host runs against a *copy* of E1's keyfile.
- **When:** the copy first runs.
- **Then:** a copied keyfile **shares** its APKAM keypair (and the key package's private half) —
  it does **not** mint its own (Decisions §3; `pq-secret-push.md` section
  [3](pq-secret-push.md#3-recipient-granularity--apkam-level-not-per-client)). The two hosts are
  the **same** APKAM keypair = one recipient; secrets already sealed to that keypair's key
  package are openable on both. Multiple-APKAM-per-enrollment arises from separate
  installs/enrolment-time mints, not from copying a keyfile. Revocation is per-keyfile-key (per
  APKAM keypair), so revoking that keypair cuts every host sharing the copy at once.

**UC-A2.3 — Namespace-restricted enrollment**
- **Given:** `@alice` pq-native; `alice1` (E1, `*`) approves `alice3` for namespace `app_1.my_apps` only (E3).
- **When:** `alice3` enrolls.
- **Then:** `alice3` gets `pqpublickey@alice⁻¹` (root — universal) and, by **approval-time push**
  (sealed per-APKAM to `alice3`'s key package via `__ssenv`), only `nskey⁻¹` for the granted
  `app_1.my_apps`; the `app_2.my_apps` nskey is never delivered. The boundary is enforced at the
  atServer `__ssenv` namespace delivery gate (it will not deliver an `…__ssenv.app_2.my_apps` key
  to an enrollment lacking `r` on it; `pq-secret-push.md` section
  [5](pq-secret-push.md#5-authorization--safety)), not by a client-side refusal alone.

## A3 · E2EE within one atSign (self data)

**UC-A3.1 — Self write/read, namespace key already exists**
- **Given:** `@alice` pq-native; the **self nskey** for `app_1.my_apps@alice` exists; alice1 & alice2 (both APKAM keypairs) hold both nskey privates.
- **When:** `alice1` puts self key `<k>.app_1.my_apps@alice`.
- **Then:** via the **nskey data path** — `alice1` cuts a symmetric **CK**, conveys it **once** as
  an `at/nskey` record (the CK X-Wing-sealed to @alice's **self nskey**); the data value is
  `at/symmetric/AES/GCM` (AES-256-GCM under the CK) and cites the CK by `kid` — no inline sealed
  key. `alice2` syncs the conveyance, **decapsulates** the CK with the self-nskey private, then
  AES-GCM-decrypts the value; no legacy provider used.

**UC-A3.2 — First self write in a namespace mints + distributes `nskey.app_1.my_apps@alice`**
- **Given:** `@alice` pq-native; no `public:nskey.app_1.my_apps@alice` yet; alice1 & alice2 PQ.
- **When:** `alice1` puts the first `app_1.my_apps` self key.
- **Then:** `alice1` mints the `app_1.my_apps` namespace keypairs — **both** the self nskey
  `nskey.app_1.my_apps@alice` and the public nskey `public:nskey.app_1.my_apps@alice` (immutable),
  holding both privates — then **pushes** both privates to every ≥`r` member **per-APKAM**: it
  calls `enroll:listfornamespace:app_1.my_apps`, seals each private to each member's key package,
  and writes `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice` (`pq-secret-push.md` section
  [6.2](pq-secret-push.md#62-newly-minted-nskey-pushed-to-all-members-req-1)). `alice2` receives
  the push, verifies correspondence, `putIfNewer` stores; both can read. `requestSecret` is the
  pull backstop for an APKAM keypair offline during the push.

**UC-A3.3 — Self fallback to the atSign-level PQ key (no namespace key)**
- **Given:** `@alice` pq-native; alice1 wants to write self data but no `nskey.app_1.my_apps@alice` minted and
  "seal-and-hold" not chosen.
- **When:** `alice1` puts self data.
- **Then:** still the **nskey data path**, with the **CK** sealed to `public:pqpublickey@alice`
  (root cold-start target) instead of an nskey; the data value is `at/symmetric/AES/GCM` under
  that CK — application data is never encapsulated directly to `pqpublickey`. Any authorised
  `@alice` APKAM keypair decapsulates the CK and decrypts; self-heals to the namespace's nskey on
  the first namespaced write.

| APKAM | enr | APKAM-kind | pqpk⁻¹ | nskey⁻¹ | KP |
|---|---|---|---|---|---|
| alice1 | E1 | pq | ✓ | ✓ | ✓ |
| alice2 | E2 | pq | ✓ | ✓ | ✓ |

## A4 · E2EE across atSigns (shared data)

**UC-A4.1 — alice → bob, both PQ-native, bob has the namespace key**
- **Given:** `@alice`, `@bob` pq-native; `@bob` published `public:nskey.app_1.my_apps@bob`; bob1/bob2 (APKAM keypairs) hold `nskey.app_1.my_apps@bob⁻¹`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** via the **nskey data path** — alice1 cuts a CK and conveys it **once** as a discrete
  `at/nskey` record (the CK X-Wing-sealed to **bob's published public nskey**
  `public:nskey.app_1.my_apps@bob`); the data value is `at/symmetric/AES/GCM` under that CK,
  citing it by `kid`. bob1 & bob2 sync the conveyance, decapsulate the CK with bob's public-nskey
  private, and AES-GCM-decrypt; PQ-safe end to end; alice keeps a self-copy readable by her
  authorised APKAM keypairs (CK conveyed to her self nskey).

**UC-A4.2 — alice → bob cold-start (bob has no `app_1.my_apps` key) → pqpublickey fallback**
- **Given:** `@alice`, `@bob` pq-native; `@bob` has `public:pqpublickey@bob` but **no** `public:nskey.app_1.my_apps@bob`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** still the **nskey data path**, with the **CK** sealed to bob's `public:pqpublickey@bob`
  (root cold-start target — application data is never encapsulated directly to it); every
  authorised bob APKAM keypair decapsulates the CK and reads. Upgrades to
  `public:nskey.app_1.my_apps@bob` once a bob `app_1.my_apps` APKAM keypair publishes it. (Or
  seal-and-hold for high-security `app_1.my_apps`.)

**UC-A4.3 — Multi-APKAM both ends**
- **Given:** alice1/alice2 and bob1/bob2 all PQ APKAM keypairs; bob has `public:nskey.app_1.my_apps@bob`.
- **When:** `alice2` shares with `@bob`.
- **Then:** all of bob's authorised APKAM keypairs read; all of alice's authorised APKAM keypairs
  read the self-copy; no authorised APKAM keypair is left unable to decrypt.

| APKAM | enr | APKAM-kind | pqpk⁻¹ | nskey⁻¹ | KP |
|---|---|---|---|---|---|
| alice1 | aE1 | pq | ✓ | ✓ | ✓ |
| alice2 | aE2 | pq | ✓ | ✓ | ✓ |
| bob1 | bE1 | pq | ✓ | ✓ | ✓ |
| bob2 | bE2 | pq | ✓ | ✓ | ✓ |

## A5 · Rotation & revocation (new world)

**UC-A5.1 — Rotate a namespace key (post-compromise)**
- **Given:** the `app_1.my_apps@alice` nskeys exist; alice1 wants to rotate. Two distinct levers,
  do not conflate them.
- **When (a) — coarse forward secrecy = rotate the symmetric CK:** `alice1` cuts a new CK, conveys
  it once (sealed to the self nskey), and points new writes at it. For FS it then **deletes the old
  CK's `at/nskey` conveyance record** and every APKAM keypair evicts the cached old CK. This is the
  cheap, O(1) coarse-FS lever.
- **Then (a):** old-CK-era data becomes undecryptable (the nskey private cannot help — no sealed
  copy of the old CK survives). Retaining the old conveyance instead = history access. This is the
  per-namespace FS retention knob.
- **When (b) — revocation + PCS = rotate the nskey *keypair*:** `alice1` mints the next nskey
  keypair excluding a compromised APKAM keypair, publishes the new
  `public:nskey.app_1.my_apps@alice`, and pushes the successor private to the surviving APKAM
  keypairs **per-APKAM** — seal to each surviving keypair's key package via `__ssenv`, dropping the
  revoked one (`pq-secret-push.md` section
  [6.4](pq-secret-push.md#64-rotation-pushes-the-successor-excluding-the-revoked-req-3)).
- **Then (b):** new CKs are sealed to the successor nskey; peers re-fetch and encapsulate to the
  new public nskey. This is the heavier, O(n)-per-APKAM revocation + post-compromise-security
  lever — **not cheap**, and **distinct** from CK rotation.

**UC-A5.2 — Per-APKAM auth revocation**
- **Given:** `@alice` pq-native; the keyfile holding alice2's APKAM keypair is lost; legacy APKAM already deleted.
- **When:** operator revokes `alice2`'s PQ APKAM public key (delete it on aliceS).
- **Then:** `alice2` (that APKAM keypair) can no longer authenticate; `alice1` unaffected; alice2
  gets no new secrets — excluded at **both** discovery+push (`excludeEnrollmentIds` on
  `enroll:listfornamespace`/serve) **and** the `requestSecret` pull serve (`pq-secret-push.md`
  section [7](pq-secret-push.md#7-mapping-to-the-substrate), Revocation guard).

**UC-A5.3 — Enrollment revocation**
- **Given:** enrollment E2 compromised (may hold several APKAM keypairs).
- **When:** operator revokes E2.
- **Then:** every APKAM keypair under E2 is cut at auth; pair with `nskey` keypair rotation
  excluding E2 to deny new-data keys.

---

# Part B — Retrofit / upgrade (mixtures of pre-PQ and post-PQ)

## B0 · Prerequisite — atServer upgrade

**UC-B0.1 — A PQ-capable APKAM keypair cannot PQ-upgrade against a legacy atServer**
- **Given:** `aliceS = legacy` (no PQ verbs); `alice1` is a PQ-capable build.
- **When:** `alice1` attempts the upgrade sequence.
- **Then:** the new PQ verbs (PQ-APKAM auth / multiple-APKAM / delete-pubkey / eviction) are unavailable → `alice1`
  **stays legacy**, no PQ keys minted, no harm. atServer upgrade is a hard prerequisite for
  Part B.

## B1 · Upgrade an existing (pre-PQ) atSign — the three scenarios

Start state for B1: `@alice = legacy`, `aliceS = pq`, no `pqpublickey` yet.

| APKAM | enr | APKAM-kind | pqpk⁻¹ | KP | note |
|---|---|---|---|---|---|
| alice1 | E1 | rsa | — | — | first to upgrade |
| alice2 | E1 | rsa | — | — | second install on same enrollment (B1.2) |
| alice3 | E2 | rsa | — | — | different enrollment (B1.3) |

**UC-B1.1 — First APKAM keypair to upgrade (`alice1`)**
- **Given:** above; `pqpublickey` absent.
- **When:** `alice1` runs the upgrade sequence.
- **Then:** mints its PQ APKAM keypair + X-Wing key package locally (both privates stay in the
  keyfile), registers it in the per-APKAM enrollment record (immutable per APKAM keypair);
  verifies PQ auth; **deletes the legacy RSA APKAM pubkey**; **wins** the immutable create of
  `pqpublickey`, generates + holds + seeds its private; its key package `KP = ✓`. End:
  `alice1.APKAM = pq`, `pqpk⁻¹ = ✓`, `pqpublickey` published.

**UC-B1.2 — Second install, same enrollment (`alice2`, E1)**
- **Given:** after B1.1; `pqpublickey` exists. `alice2` is a **separate install** on E1 (its own
  enrolment-time mint, *not* a copied keyfile — a copy would share alice1's keypair, see UC-A2.2).
- **When:** `alice2` runs the sequence.
- **Then:** mints its **own** PQ APKAM keypair + key package (so E1 now holds **two** APKAM
  keypairs, two key packages — multiple-per-enrollment), registers it; verifies PQ auth;
  **requests** `pqpublickey@alice⁻¹` (exists → does not create), verifies correspondence, stores.
  Identical to B1.1 except step 6 is *request*, not *create*.

**UC-B1.3 — Third APKAM keypair, different enrollment (`alice3`, E2)**
- **Given:** after B1.1; `pqpublickey` exists.
- **When:** `alice3` runs the sequence.
- **Then:** identical to B1.2 for this bootstrap (mints own PQ APKAM keypair + key package,
  requests root `pqpublickey@alice⁻¹`). Distinction appears only for **namespaced** secrets — a
  restricted E2 receives a subset of `nskey` keys.

## B2 · Legacy APKAM deletion consequences

**UC-B2.1 — Un-upgraded copy is locked out after deletion**
- **Given:** E1's keyfile was copied to a second host `alice1b` (against advice) — the **same**
  legacy APKAM keypair on two hosts; `alice1` upgraded (minting a *new* PQ APKAM keypair) and
  deleted the shared legacy APKAM pubkey; `alice1b` has not upgraded.
- **When:** `alice1b` tries to authenticate (legacy).
- **Then:** auth **fails** (the shared legacy pubkey is gone, and `alice1b` never minted its own PQ
  keypair); `alice1b` must re-enroll. Acceptance: this is the intended enforcement of "one APKAM
  keypair per keyfile" — revocation is per-keyfile-key (per APKAM keypair), so deleting the shared
  legacy keypair cuts the un-upgraded copy.

**UC-B2.2 — Grace-period variant**
- **Given:** deployment opted into a grace period.
- **When:** `alice1` upgrades.
- **Then:** legacy auth survives N days then auto-deletes; `alice1b` can upgrade within the
  window (minting its own PQ APKAM keypair); after it, UC-B2.1 applies. (Bypass open during the
  window — explicit trade-off.)

## B3 · Mixed-PQ within one atSign (some APKAM keypairs upgraded)

**UC-B3.1 — Upgraded APKAM keypair must still write legacy for an un-upgraded sibling**
- **Given:** `alice1` is PQ (`APKAM = pq`, holds the nskey/`pqpublickey` privates), `alice2` still
  legacy-only; `@alice` readiness `n-r`.
- **When:** `alice1` writes a self key both must read.
- **Then:** `alice1` writes **legacy** (the scheme alice2 can read) — migration invariant
  "write only what every reader supports"; no data is unreadable by alice2.

**UC-B3.2 — Readiness flips once all `@alice` APKAM keypairs are upgraded**
- **Given:** all `@alice` APKAM keypairs now PQ; operator (or auto-detect) flips readiness `ready`.
- **When:** `alice1` writes self data.
- **Then:** self data goes via the **nskey data path** — `at/nskey` conveys the CK (sealed to the
  self nskey, or to `public:pqpublickey@alice` as the cold-start CK target) and
  `at/symmetric/AES/GCM` encrypts the data; the data is never encapsulated directly to the
  nskey/`pqpublickey`. No `@alice` APKAM keypair loses access.

| APKAM | enr | APKAM-kind | data-reads | data-writes |
|---|---|---|---|---|
| alice1 | E1 | pq | legacy + nskey data path | legacy (until ready) → nskey data path |
| alice2 | E1 | rsa | legacy | legacy |

## B4 · Mixed-PQ across atSigns

**UC-B4.1 — PQ-ready `@alice` shares with legacy `@bob`**
- **Given:** `@alice` PQ-ready; `@bob` legacy (only `publickey` RSA), bob readiness `n-r`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** alice writes **legacy** to bob (gated by bob's readiness); a PQ self-copy via the
  nskey data path for alice's own authorised APKAM keypairs is allowed independently. No write bob
  can't read.

**UC-B4.2 — Legacy `@alice` receives from PQ `@bob` (and the interop question)**
- **Given:** `@alice` legacy (no `pqpublickey`); `@bob` PQ-native.
- **When:** `bob1` shares with `@alice`.
- **Then:** bob must encapsulate in a scheme alice can read → **legacy RSA to alice's
  `public:publickey@alice`**, which exists only if alice enabled the legacy-interop flag
  (default off). **Resolved:** a PQ-native atSign is PQ-only by default, so legacy-peer send
  to it is **unsupported unless** that flag is on (UC-A1.1).

**UC-B4.3 — Partially-upgraded `@alice` (alice1 PQ, alice2 legacy) shares with `@bob`**
- **Given:** `@alice` mixed; `@bob` PQ-ready.
- **When:** `alice1` shares with `@bob`.
- **Then:** to `@bob` the write may be PQ via the nskey data path (bob is ready); but alice's
  **self-copy** must be legacy (alice2 can't read PQ) until `@alice` readiness flips. Two
  directions, two schemes, same `put`.

**UC-B4.4 — `@bob` finishes upgrading → shared flips to PQ**
- **Given:** `@bob` was legacy; now all bob APKAM keypairs PQ and bob readiness `ready`.
- **When:** `alice1` next shares with `@bob`.
- **Then:** alice writes via the **nskey data path** to bob (`at/nskey` conveys the CK sealed to
  bob's public nskey, or `public:pqpublickey@bob` cold-start; `at/symmetric/AES/GCM` encrypts the
  data); legacy path no longer needed for bob.

## B5 · Retrofit edge cases

**UC-B5.1 — Offline APKAM keypair pulls `pqpublickey` later**
- **Given:** `alice2` (an APKAM keypair) was offline during the upgrade wave; `pqpublickey` created by `alice1`.
- **When:** `alice2` next comes online and upgrades.
- **Then:** `pqpublickey` is root (no namespace), so it has no `enroll:listfornamespace` push —
  its `requestSecret` for `pqpublickey@alice⁻¹` is answered by any online holder (pull is its
  steady-state path; persists if none online until one answers). Namespaced `nskey` privates that
  `alice2` missed during its offline window arrive by the **push** primary path once a holder is
  online (`enroll:listfornamespace` + `__ssenv`), with `requestSecret` as the backstop.

**UC-B5.2 — Reading legacy history after upgrade**
- **Given:** `alice1` upgraded; legacy *encryption* key retained (only legacy APKAM deleted).
- **When:** `alice1` reads pre-PQ data.
- **Then:** decrypts via the legacy provider (reads are universal); `providerId` routes per
  value. PQ upgrade never makes old data unreadable.

**UC-B5.3 — Two APKAM keypairs race to create `pqpublickey`**
- **Given:** `alice1` and `alice3` both reach the create step with `pqpublickey` absent.
- **When:** both attempt the immutable create.
- **Then:** exactly one wins; the other gets "already exists" and falls through to *request*.
  No orphaned data (readiness not yet flipped).

---

## Decisions

Resolved 2026-06-24:

1. **Legacy-peer interop** (UC-A1.1, UC-B4.2): **config flag, default off** — a PQ-native
   atSign is PQ-only by default (no RSA `public:publickey@<atSign>`); enable the flag to
   publish it for legacy-peer inbound. A legacy peer can reach a PQ-native atSign only when
   the flag is on.
2. **Readiness granularity** (B3/B4): **per (atSign, namespace)**, plus an atSign-level marker
   for the root `pqpublickey` fallback — enabling independent per-namespace rollout.
3. **PQ APKAM placement**: **copyable keyfile** section (like the legacy APKAM). The recipient
   unit is the **APKAM keypair**, one per keyfile: a copy made *after* upgrade **shares** the
   keypair (and its key package private half) — revocation is per-keyfile-key (per APKAM keypair),
   not strictly per-device; a copy made *before* upgrade mints its own. (This is the source of
   truth UC-A2.2 / UC-B2.1 align to.) Device-local/keychain is an optional hardening for
   deployments wanting true host binding.
4. **`nskey` to a new enrollment**: **push at approve + pull backstop** — the approver conveys the
   authorised-namespace `nskey` privates **per-APKAM** via the `__ssenv` substrate (seal to each
   granted-namespace key package, `shareAllSecretsWithEnrollment`); `requestSecret` is the
   backstop. The push generalises beyond approval: steady-state mint/rotation pushes use the
   `enroll:listfornamespace` verb to enumerate ≥`r` members (`pq-secret-push.md` reqs 1/3).
   (Derive-from-seed rejected — over-grants restricted enrollments.)
5. **Seal-and-hold vs send-now** (A3.3, A4.2): **send-now via the `pqpublickey` fallback by
   default; seal-and-hold a per-namespace opt-in** for high-security namespaces.

## Coverage map (build-order checklist)

| # | Cluster | UCs | Depends on |
|---|---|---|---|
| A1 | Onboard new atSign | A1.1 | atServer `pq` |
| A2 | Enrollments | A2.1–A2.3 | A1 |
| A3 | Self e2ee | A3.1–A3.3 | A2 |
| A4 | Cross-atSign e2ee | A4.1–A4.3 | A3, peer atSign |
| A5 | Rotation/revocation | A5.1–A5.3 | A3/A4 |
| B0 | atServer upgrade | B0.1 | — |
| B1 | Upgrade existing atSign | B1.1–B1.3 | B0, A* |
| B2 | Legacy deletion | B2.1–B2.2 | B1 |
| B3 | Mixed within atSign | B3.1–B3.2 | B1 |
| B4 | Mixed across atSigns | B4.1–B4.4 | B1, B3 |
| B5 | Retrofit edges | B5.1–B5.3 | B1 |
