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
  - [A2 · Enrollments (a new client joins)](#a2--enrollments-a-new-client-joins)
  - [A3 · E2EE within one atSign (self data)](#a3--e2ee-within-one-atsign-self-data)
  - [A4 · E2EE across atSigns (shared data)](#a4--e2ee-across-atsigns-shared-data)
  - [A5 · Rotation & revocation (new world)](#a5--rotation--revocation-new-world)
- [Part B — Retrofit / upgrade (mixtures of pre-PQ and post-PQ)](#part-b--retrofit--upgrade-mixtures-of-pre-pq-and-post-pq)
  - [B0 · Prerequisite — atServer upgrade](#b0--prerequisite--atserver-upgrade)
  - [B1 · Upgrade an existing (pre-PQ) atSign — the three scenarios](#b1--upgrade-an-existing-pre-pq-atsign--the-three-scenarios)
  - [B2 · Legacy APKAM deletion consequences](#b2--legacy-apkam-deletion-consequences)
  - [B3 · Mixed-PQ within one atSign (some clients upgraded)](#b3--mixed-pq-within-one-atsign-some-clients-upgraded)
  - [B4 · Mixed-PQ across atSigns](#b4--mixed-pq-across-atsigns)
  - [B5 · Retrofit edge cases](#b5--retrofit-edge-cases)
- [Decisions](#decisions)
- [Coverage map (build-order checklist)](#coverage-map-build-order-checklist)

## Notation & state model

**Actors.** `@alice`, `@bob` are atSigns. `alice1`, `alice2`, `alice3` are *clients*
(a client = one running instance bound to one keyfile/keychain on one host) of `@alice`;
likewise `bob1`, `bob2`. `aliceS` / `bobS` are their atServers.

**Per-client state** (table columns):

| Col | Meaning |
|---|---|
| `enr` | enrollment the client is on (`E1`, `E2`, …) |
| `APKAM` | auth keypair held: `rsa` (legacy) · `pq` (ML-DSA) · `both` |
| `pqpk⁻¹` | holds the atSign-level `pqpublickey` **private** half? |
| `nskey⁻¹` | holds its **own** atSign's namespace keypair **private** half, per namespace (an `@alice` client holds `nskey.<ns>@alice`'s private) — see *Namespace key shapes* |
| `CKP` | has published its `ClientKeyPackage` (X-Wing, for receiving sealed secrets)? |

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
| `nskey.app_1.my_apps@alice` | @alice's namespace **keypair** (self) — alice's own clients hold the **private** half, decrypting both her self data and inbound shares |
| `public:nskey.app_1.my_apps@alice` | its **public** half, **published world-readable** — **any** atSign (a peer, or alice for her own self data) encapsulates to it to send to @alice |
| `nskey.app_1.my_apps@bob` | @bob's namespace keypair (self) — symmetric; bob's clients hold its private half |
| `public:nskey.app_1.my_apps@bob` | @bob's **published public** half — any atSign (incl. @alice) encapsulates to it to send to @bob |

The private half is held only by the owning atSign's own clients (the `nskey⁻¹` column); the
`public:` form is the one published key anyone encapsulates to — there is **no** per-recipient
key shape.

**atServer PQ capabilities** (Part A and B both assume `aS = pq` unless stated): the
**existing** immutable write (`Metadata.immutable`) for mint-once, plus the **new** verbs —
multiple APKAM keys per enrollment + auth-against-any · PQ (ML-DSA) APKAM auth · delete a
specific pubkey · TTL/usage eviction of APKAM keys.

---

# Part A — The new world (PQ-native, PQ-capable atServer)

## A1 · Onboard a new atSign

**UC-A1.1 — First-client CRAM onboard is PQ-native**
- **Given:** `@alice` unactivated; `aliceS = pq`; no keys exist.
- **When:** `alice1` runs CRAM onboarding.
- **Then:** `alice1.APKAM = pq` and it authenticates via PQ APKAM; `public:pqpublickey@alice`
  is published (immutable) and `alice1.pqpk⁻¹ = ✓`; `alice1.CKP = ✓`; readiness can be
  `ready` (no legacy clients exist). **Legacy interop is a config flag (default off):** by
  default a PQ-native atSign is PQ-only — no RSA `public:publickey@alice`; enable the flag to
  publish it for legacy-peer inbound (see UC-B4.2).

| client | enr | APKAM | pqpk⁻¹ | nskey⁻¹ | CKP |
|---|---|---|---|---|---|
| alice1 | E1 | pq | ✓ | — | ✓ |

## A2 · Enrollments (a new client joins)

**UC-A2.1 — New enrollment, approved by an online client (PQ-safe enroll/approve)**
- **Given:** `@alice` pq-native; `pqpublickey` published; `alice1` enrolled (E1) & online.
- **When:** `alice2` requests enrollment (E2); `alice1` approves.
- **Then:** `alice2.APKAM = pq` (its own); `alice2.pqpk⁻¹ = ✓` (pushed by approver over the
  **PQ** enrollment-conveyance key, *not* RSA-wrapped); `alice2.CKP = ✓`; `alice2` can
  authenticate PQ and decrypt `@alice`'s PQ self data within its authorised namespaces.

**UC-A2.2 — Second host on the *same* enrollment (copied keyfile, E1)**
- **Given:** `@alice` pq-native; `alice1` on E1; `alice2` is a second host using E1's keyfile.
- **When:** `alice2` first runs.
- **Then:** per the *multiple-APKAM-per-enrollment* rule, `alice2` mints its **own** PQ APKAM
  keypair (host-local), publishes it as a distinct per-host record; obtains `pqpublickey@alice⁻¹`
  (already in the copied keyfile, or pulled). One enrollment now has **two** PQ APKAM keys,
  individually revocable.

**UC-A2.3 — Namespace-restricted enrollment**
- **Given:** `@alice` pq-native; `alice1` (E1, `*`) approves `alice3` for namespace `app_1.my_apps` only (E3).
- **When:** `alice3` enrolls.
- **Then:** `alice3` gets `pqpublickey@alice⁻¹` (root — universal) but only `nskey⁻¹` for `app_1.my_apps`; a
  request for `app_2.my_apps`'s key is refused (namespace = authz boundary).

## A3 · E2EE within one atSign (self data)

**UC-A3.1 — Self write/read, namespace key already exists**
- **Given:** `@alice` pq-native; `public:nskey.app_1.my_apps@alice` published; alice1 & alice2 hold `nskey.app_1.my_apps@alice⁻¹`.
- **When:** `alice1` puts self key `<k>.app_1.my_apps@alice`.
- **Then:** value encapsulated to @alice's own published public key `public:nskey.app_1.my_apps@alice`; `providerId = nskey`;
  `alice2` decrypts with `nskey.app_1.my_apps@alice⁻¹`; no legacy provider used.

**UC-A3.2 — First self write in a namespace mints + distributes `nskey.app_1.my_apps@alice`**
- **Given:** `@alice` pq-native; no `public:nskey.app_1.my_apps@alice` yet; alice1 & alice2 PQ.
- **When:** `alice1` puts the first `app_1.my_apps` self key.
- **Then:** `alice1` mints the `app_1.my_apps` namespace keypair `nskey.app_1.my_apps@alice`, publishes `public:nskey.app_1.my_apps@alice` (immutable),
  seeds `nskey.app_1.my_apps@alice⁻¹` as an `app_1.my_apps`-namespaced secret; `alice2` obtains it via `requestSecret`
  (authorised for `app_1.my_apps`), verifies correspondence, stores; both can read.

**UC-A3.3 — Self fallback to the atSign-level PQ key (no namespace key)**
- **Given:** `@alice` pq-native; alice1 wants to write self data but no `nskey.app_1.my_apps@alice` minted and
  "seal-and-hold" not chosen.
- **When:** `alice1` puts self data.
- **Then:** encapsulated to `public:pqpublickey@alice` (root fallback); any `@alice` client decrypts;
  self-heals to `nskey` on first namespaced write.

| client | enr | APKAM | pqpk⁻¹ | nskey⁻¹ | CKP |
|---|---|---|---|---|---|
| alice1 | E1 | pq | ✓ | ✓ | ✓ |
| alice2 | E2 | pq | ✓ | ✓ | ✓ |

## A4 · E2EE across atSigns (shared data)

**UC-A4.1 — alice → bob, both PQ-native, bob has the namespace key**
- **Given:** `@alice`, `@bob` pq-native; `@bob` published `public:nskey.app_1.my_apps@bob`; bob1/bob2 hold `nskey.app_1.my_apps@bob⁻¹`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** data key encapsulated to **bob's** published public key `public:nskey.app_1.my_apps@bob`; `providerId = nskey`;
  bob1 & bob2 both decrypt; PQ-safe end to end; alice keeps a self-copy readable by her clients.

**UC-A4.2 — alice → bob cold-start (bob has no `app_1.my_apps` key) → pqpublickey fallback**
- **Given:** `@alice`, `@bob` pq-native; `@bob` has `public:pqpublickey@bob` but **no** `public:nskey.app_1.my_apps@bob`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** encapsulated to bob's `public:pqpublickey@bob` (every bob client can read); upgrades to
  `public:nskey.app_1.my_apps@bob` once a bob `app_1.my_apps` client publishes it. (Or seal-and-hold for high-security `app_1.my_apps`.)

**UC-A4.3 — Multi-client both ends**
- **Given:** alice1/alice2 and bob1/bob2 all PQ; bob has `public:nskey.app_1.my_apps@bob`.
- **When:** `alice2` shares with `@bob`.
- **Then:** all of bob's authorised clients read; all of alice's authorised clients read the
  self-copy; no client is left unable to decrypt.

| client | enr | APKAM | pqpk⁻¹ | nskey⁻¹ | CKP |
|---|---|---|---|---|---|
| alice1 | aE1 | pq | ✓ | ✓ | ✓ |
| alice2 | aE2 | pq | ✓ | ✓ | ✓ |
| bob1 | bE1 | pq | ✓ | ✓ | ✓ |
| bob2 | bE2 | pq | ✓ | ✓ | ✓ |

## A5 · Rotation & revocation (new world)

**UC-A5.1 — Rotate a namespace key (post-compromise)**
- **Given:** `nskey.app_1.my_apps@alice` exists; alice1 wants to rotate.
- **When:** `alice1` mints `nskey.app_1.my_apps@alice` epoch+1, publishes the new `public:nskey.app_1.my_apps@alice`, distributes the new
  private excluding nobody.
- **Then:** new writes use epoch+1; clients retain old private to read old data (no FS);
  peers re-encapsulate to the new pubkey.

**UC-A5.2 — Per-host auth revocation**
- **Given:** `@alice` pq-native; alice2's host is lost; legacy APKAM already deleted.
- **When:** operator revokes `alice2`'s PQ APKAM public key (delete it on aliceS).
- **Then:** `alice2` can no longer authenticate; `alice1` unaffected; alice2 gets no new
  secrets (excluded from future `requestSecret` serves).

**UC-A5.3 — Enrollment revocation**
- **Given:** enrollment E2 compromised (may span hosts).
- **When:** operator revokes E2.
- **Then:** every host of E2 is cut at auth; pair with `nskey` rotation excluding E2 to deny
  new-data keys.

---

# Part B — Retrofit / upgrade (mixtures of pre-PQ and post-PQ)

## B0 · Prerequisite — atServer upgrade

**UC-B0.1 — Client cannot PQ-upgrade against a legacy atServer**
- **Given:** `aliceS = legacy` (no PQ verbs); `alice1` is a PQ-capable build.
- **When:** `alice1` attempts the upgrade sequence.
- **Then:** the new PQ verbs (PQ-APKAM auth / multiple-APKAM / delete-pubkey / eviction) are unavailable → `alice1`
  **stays legacy**, no PQ keys minted, no harm. atServer upgrade is a hard prerequisite for
  Part B.

## B1 · Upgrade an existing (pre-PQ) atSign — the three scenarios

Start state for B1: `@alice = legacy`, `aliceS = pq`, no `pqpublickey` yet.

| client | enr | APKAM | pqpk⁻¹ | CKP | note |
|---|---|---|---|---|---|
| alice1 | E1 | rsa | — | — | first to upgrade |
| alice2 | E1 | rsa | — | — | same enrollment (B1.2) |
| alice3 | E2 | rsa | — | — | different enrollment (B1.3) |

**UC-B1.1 — First client to upgrade (`alice1`)**
- **Given:** above; `pqpublickey` absent.
- **When:** `alice1` runs the upgrade sequence.
- **Then:** mints PQ APKAM (host-local), publishes it (immutable per-host); verifies PQ auth;
  **deletes the legacy RSA APKAM pubkey**; **wins** the immutable create of `pqpublickey`,
  generates + holds + seeds its private; publishes CKP. End: `alice1.APKAM = pq`,
  `pqpk⁻¹ = ✓`, `pqpublickey` published.

**UC-B1.2 — Second client, same enrollment (`alice2`, E1)**
- **Given:** after B1.1; `pqpublickey` exists.
- **When:** `alice2` runs the sequence.
- **Then:** mints its **own** PQ APKAM (multiple-per-enrollment), publishes it; verifies PQ
  auth; **requests** `pqpublickey@alice⁻¹` (exists → does not create), verifies correspondence,
  stores. Identical to B1.1 except step 6 is *request*, not *create*.

**UC-B1.3 — Third client, different enrollment (`alice3`, E2)**
- **Given:** after B1.1; `pqpublickey` exists.
- **When:** `alice3` runs the sequence.
- **Then:** identical to B1.2 for this bootstrap (mints own PQ APKAM, requests root
  `pqpublickey@alice⁻¹`). Distinction appears only for **namespaced** secrets — a restricted E2
  receives a subset of `nskey` keys.

## B2 · Legacy APKAM deletion consequences

**UC-B2.1 — Un-upgraded copy is locked out after deletion**
- **Given:** E1's keyfile was copied to a second host `alice1b` (against advice); `alice1`
  upgraded and deleted the legacy APKAM pubkey; `alice1b` has not upgraded.
- **When:** `alice1b` tries to authenticate (legacy).
- **Then:** auth **fails** (legacy pubkey gone); `alice1b` must re-enroll. Acceptance: this is
  the intended enforcement of "one enrollment key per keyfile."

**UC-B2.2 — Grace-period variant**
- **Given:** deployment opted into a grace period.
- **When:** `alice1` upgrades.
- **Then:** legacy auth survives N days then auto-deletes; `alice1b` can upgrade within the
  window; after it, UC-B2.1 applies. (Bypass open during the window — explicit trade-off.)

## B3 · Mixed-PQ within one atSign (some clients upgraded)

**UC-B3.1 — Upgraded client must still write legacy for an un-upgraded sibling**
- **Given:** `alice1.APKAM/enc = pq`, `alice2` still legacy-only; `@alice` readiness `n-r`.
- **When:** `alice1` writes a self key both must read.
- **Then:** `alice1` writes **legacy** (the scheme alice2 can read) — migration invariant
  "write only what every reader supports"; no data is unreadable by alice2.

**UC-B3.2 — Readiness flips once all `@alice` clients are upgraded**
- **Given:** all `@alice` clients now PQ; operator (or auto-detect) flips readiness `ready`.
- **When:** `alice1` writes self data.
- **Then:** self data goes `nskey`/`pqpublickey` (PQ); no `@alice` client loses access.

| client | enr | APKAM | enc-reads | enc-writes |
|---|---|---|---|---|
| alice1 | E1 | pq | legacy+pq | legacy (until ready) → pq |
| alice2 | E1 | rsa | legacy | legacy |

## B4 · Mixed-PQ across atSigns

**UC-B4.1 — PQ-ready `@alice` shares with legacy `@bob`**
- **Given:** `@alice` PQ-ready; `@bob` legacy (only `publickey` RSA), bob readiness `n-r`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** alice writes **legacy** to bob (gated by bob's readiness); PQ self-copy for alice's
  own clients is allowed independently. No write bob can't read.

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
- **Then:** to `@bob` the write may be PQ (bob is ready); but alice's **self-copy** must be
  legacy (alice2 can't read PQ) until `@alice` readiness flips. Two directions, two schemes,
  same `put`.

**UC-B4.4 — `@bob` finishes upgrading → shared flips to PQ**
- **Given:** `@bob` was legacy; now all bob clients PQ and bob readiness `ready`.
- **When:** `alice1` next shares with `@bob`.
- **Then:** alice writes `nskey`/`pqpublickey` PQ to bob; legacy path no longer needed for bob.

## B5 · Retrofit edge cases

**UC-B5.1 — Offline client pulls `pqpublickey` later**
- **Given:** `alice2` was offline during the upgrade wave; `pqpublickey` created by `alice1`.
- **When:** `alice2` next comes online and upgrades.
- **Then:** its `requestSecret` for `pqpublickey@alice⁻¹` is answered by any online holder; persists
  if none online until one answers.

**UC-B5.2 — Reading legacy history after upgrade**
- **Given:** `alice1` upgraded; legacy *encryption* key retained (only legacy APKAM deleted).
- **When:** `alice1` reads pre-PQ data.
- **Then:** decrypts via the legacy provider (reads are universal); `providerId` routes per
  value. PQ upgrade never makes old data unreadable.

**UC-B5.3 — Two clients race to create `pqpublickey`**
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
3. **PQ APKAM placement**: **copyable keyfile** section (like the legacy APKAM). A copy made
   *after* upgrade shares the key (revocation is per-keyfile-key, not strictly per-device); a
   copy made *before* upgrade mints its own. Device-local/keychain is an optional hardening for
   deployments wanting true per-host binding.
4. **`nskey` to a new enrollment**: **push at approve + pull fallback** — the approver conveys
   the authorised-namespace `nskey` privates in the enroll/approve bundle; `requestSecret` is
   the backstop. (Derive-from-seed rejected — over-grants restricted enrollments.)
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
