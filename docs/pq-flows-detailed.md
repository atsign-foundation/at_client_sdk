# PQ crypto — detailed flows (given / when / then)

**Status:** working planning doc (not plan-of-record). Lives in `docs/`.
**Companion to** `pq-use-case-catalogue.md` — this elaborates the flows into protocol
step sequences and testable acceptance ("then"). IDs (UC-A1.1 …) reference the catalogue.

**Conventions.** Notation per the catalogue. Each flow gives **Given** (state),
**When** (trigger), **Steps** (the protocol sequence), **Then** (acceptance — testable
assertions). "Working name" marks an at-key name not yet finalised. `aS = pq` (PQ-capable
atServer) unless stated.

Key objects used throughout:
- `public:pqpublickey@alice` — atSign-level PQ encryption pubkey (X-Wing; root, no
  namespace; **immutable** once written). Private half = the root secret `pqid:<kid>`.
- **PQ APKAM** keypair — ML-DSA signing key for auth; minted **per APKAM keypair**
  (one per keyfile/install, multiple per enrollment); public half registered in the
  **per-APKAM enrollment record** (working name
  `<enrollmentId>.<apkamId>.pqapkam.__manage@alice`, immutable per APKAM keypair).
- **Namespace key** (`nskey`) — **two** per-`(atSign, namespace)` X-Wing KEM keypairs (a **self
  nskey** and a **public nskey**). nskey is asymmetric and only ever **wraps symmetric content
  keys (CKs)** — it never encrypts application data directly; its private **decapsulates CKs**. With
  namespace `app_1.my_apps` (key name `nskey`, namespace `app_1.my_apps` — namespaces read
  right-to-left, DNS-style: app `app_1` under org `my_apps`), the at-key shapes recur — keep them
  distinct:
  - **self nskey** (`nskey.app_1.my_apps@alice`, public half **not** published) — alice encapsulates
    **her own** CKs to it; alice's clients hold the **private** half (decapsulates her own CKs).
  - `public:nskey.app_1.my_apps@alice` — the **public nskey** public half, **published
    world-readable**; **external senders** encapsulate CKs to it to send to @alice; alice's clients
    hold its private (decapsulates CKs inbound senders sent her).
  - `@bob`'s self nskey + `public:nskey.app_1.my_apps@bob`, symmetric.
  The private halves are conveyed **per-APKAM** by the secret-sharing substrate (PUSH at
  mint/approve/rotate via the gated `enroll:listfornamespace` verb + the `__ssenv` envelope;
  `requestSecret` PULL as the offline backstop), held only by the owning atSign's own APKAM
  keypairs. There are **two** nskeys per namespace (self + public): self data uses the unpublished
  self nskey; cross-atSign uses the recipient's published public nskey.
- **X-Wing key package** — the per-APKAM X-Wing recipient keypair a sender `pqSeal`s to (its
  `kpid` = the kid of its X-Wing public half). Generated locally with each APKAM keypair;
  **registered in the per-APKAM enrollment record** (`<enrollmentId>.<apkamId>.pqapkam.__manage@alice`)
  alongside the ML-DSA APKAM pubkey — **never published**, never a client-published at-key,
  discovered only via the gated `enroll:listfornamespace` verb. Its **private half never leaves
  the keyfile**.
- `appMetadata.providerId ∈ {legacy, at/nskey, at/symmetric/AES/GCM}` — routes the reader to a
  provider; a value with **no** `providerId` defaults to **legacy**. `at/nskey` tags a
  CK-conveyance record (a CK X-Wing-sealed to an nskey); `at/symmetric/AES/GCM` tags application
  data AES-256-GCM under a CK, cited by `ckKid`. (`at/nskey` only **conveys** the CK — it never
  encrypts application data; the umbrella for `at/nskey` + `at/symmetric/AES/GCM` is the **nskey
  data path**.)

---

## Table of contents

- [1. Onboarding & enrollment](#1-onboarding--enrollment)
  - [1.1 Onboard a new atSign (PQ-native) — UC-A1.1](#11-onboard-a-new-atsign-pq-native--uc-a11)
  - [1.2 Enroll a new client — PQ-safe enroll/approve — UC-A2.1](#12-enroll-a-new-client--pq-safe-enrollapprove--uc-a21)
  - [1.3 Second host on the *same* enrollment — UC-A2.2](#13-second-host-on-the-same-enrollment--uc-a22)
  - [1.4 Namespace-restricted enrollment — UC-A2.3](#14-namespace-restricted-enrollment--uc-a23)
- [2. Upgrade paths (existing pre-PQ atSign)](#2-upgrade-paths-existing-pre-pq-atsign)
  - [2.0 atServer upgrade is a prerequisite — UC-B0.1](#20-atserver-upgrade-is-a-prerequisite--uc-b01)
  - [2.1 First client upgrade — UC-B1.1](#21-first-client-upgrade--uc-b11)
  - [2.2 Second client, same enrollment — UC-B1.2](#22-second-client-same-enrollment--uc-b12)
  - [2.3 Third client, different enrollment — UC-B1.3](#23-third-client-different-enrollment--uc-b13)
  - [2.4 Legacy APKAM deletion & lockout — UC-B2.1 / B2.2](#24-legacy-apkam-deletion--lockout--uc-b21--b22)
- [3. E2EE within one atSign (self) — puts & notifications](#3-e2ee-within-one-atsign-self--puts--notifications)
  - [3.1 Self put, namespace key exists — UC-A3.1](#31-self-put-namespace-key-exists--uc-a31)
  - [3.2 First self put in a namespace mints + distributes both `nskey.app_1.my_apps@alice` keypairs — UC-A3.2](#32-first-self-put-in-a-namespace-mints--distributes-both-nskeyapp_1my_appsalice-keypairs--uc-a32)
  - [3.3 Self put falls back to `pqpublickey` (no namespace key) — UC-A3.3](#33-self-put-falls-back-to-pqpublickey-no-namespace-key--uc-a33)
  - [3.4 Self notification — NEW](#34-self-notification--new)
  - [3.5 Mixed — upgraded `alice1`, un-upgraded `alice2` — UC-B3.1](#35-mixed--upgraded-alice1-un-upgraded-alice2--uc-b31)
- [4. E2EE across atSigns — shares & notifications](#4-e2ee-across-atsigns--shares--notifications)
  - [4.1 Shared put, recipient has the namespace key — UC-A4.1](#41-shared-put-recipient-has-the-namespace-key--uc-a41)
  - [4.2 Shared put cold-start → `pqpublickey` fallback — UC-A4.2](#42-shared-put-cold-start--pqpublickey-fallback--uc-a42)
  - [4.3 Cross-atSign notification — NEW](#43-cross-atsign-notification--new)
  - [4.4 Mixed PQ/legacy across atSigns — UC-B4.1 / B4.3 / B4.4](#44-mixed-pqlegacy-across-atsigns--uc-b41--b43--b44)
- [Cross-cutting acceptance (applies to all flows)](#cross-cutting-acceptance-applies-to-all-flows)
- [Decisions (see catalogue)](#decisions-see-catalogue)

# 1. Onboarding & enrollment

## 1.1 Onboard a new atSign (PQ-native) — UC-A1.1

- **Given:** `@alice` unactivated; `aliceS = pq`; CRAM activation secret in hand; no keys.
- **When:** `alice1` runs onboarding.
- **Steps:**
  1. CRAM-authenticate with the activation secret.
  2. Mint **PQ APKAM** keypair (ML-DSA); register its public half in the per-APKAM enrollment
     record; set it as this enrollment's (E1) APKAM key.
  3. Mint the atSign-level **X-Wing** keypair; **immutable-create** `public:pqpublickey@alice`;
     keep the private half locally and seed it as `pqid:<kid>`.
  4. Mint this APKAM keypair's **X-Wing key package** and register it in the per-APKAM enrollment
     record (private half stays in the keyfile; **not** published).
  5. Persist AtKeys (PQ APKAM private + `pqpublickey@alice⁻¹` + X-Wing key package private half)
     to the per-APKAM keyfile/keychain.
  6. **Verify**: re-authenticate using the PQ APKAM key (proves the server accepts PQ auth).
  7. Legacy interop (config flag, **default off**): publish `public:publickey@alice` (RSA)
     **only if enabled**, for legacy-peer inbound; default is PQ-only (omit it).
- **Then (acceptance):**
  - `alice1` authenticates with PQ APKAM; no RSA APKAM key is required for auth.
  - `public:pqpublickey@alice` exists, is immutable (a second create attempt is rejected),
    and `alice1` holds its private half.
  - `alice1`'s X-Wing key package is registered in its per-APKAM enrollment record (not
    published; discoverable only via `enroll:listfornamespace`).
  - No `selfEncryptionKey` is minted (self data will use the **nskey data path** — `at/nskey`
    conveys the CK, `at/symmetric/AES/GCM` encrypts the data; cold-start seals the CK to
    `pqpublickey`).
  - readiness may be `ready` (no legacy clients exist).
  - *(Legacy-interop flag on)* `public:publickey@alice` is present; **default (flag off)** it is
    absent and a legacy peer's send is unsupported (UC-B4.2).

## 1.2 Enroll a new client — PQ-safe enroll/approve — UC-A2.1

- **Given:** `@alice` pq-native; `pqpublickey` published; `alice1` (E1) online and able to approve.
- **When:** `alice2` requests a new enrollment (E2) for namespaces `[app_1.my_apps]`; `alice1` approves.
- **Steps:**
  1. `alice2` mints its own **PQ APKAM** keypair and an `apkamSymmetricKey`.
  2. `alice2` **encapsulates** `apkamSymmetricKey` to `@alice`'s `pqpublickey` (X-Wing) — **not**
     RSA — and sends `enroll:request` with its PQ APKAM public half + requested namespaces.
  3. `alice1` (approver) decapsulates `apkamSymmetricKey` with `pqpublickey@alice⁻¹`; approves E2;
     registers `alice2`'s PQ APKAM pubkey for E2 (multiple-per-enrollment).
  4. `alice1` conveys the secrets `alice2` is authorised for:
     - the **`pqpublickey@alice⁻¹`** (root) rides the approval response bundle (wrapped under
       `apkamSymmetricKey`);
     - the **`nskey.app_1.my_apps@alice⁻¹`** (authorised namespace only) is delivered by the
       **substrate push** — `alice1` `pqSeal`s it to `alice2`'s X-Wing key package and `put`s it
       to `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice` (this is
       `shareAllSecretsWithEnrollment(E2, approvedNamespaces)`, re-keyed to APKAM-level).
  5. `alice2` consumes the substrate envelope + approval bundle, decapsulates, verifies; registers
     its **X-Wing key package** in its per-APKAM enrollment record; persists AtKeys.
  6. `alice2` verifies PQ APKAM auth.
- **Then:**
  - Nothing in the conveyance path is RSA-wrapped (`apkamSymmetricKey` rode X-Wing) — the
    enrollment harvest-now hole is closed.
  - `alice2.APKAM = pq`, `pqpk⁻¹ = ✓`, `nskey.app_1.my_apps@alice⁻¹ = ✓`, `nskey.app_2.my_apps@alice⁻¹ = ✗`, X-Wing key package registered.
  - `alice2` can authenticate PQ and decrypt `@alice`'s `app_1.my_apps` self data; a `app_2.my_apps` key request
    is refused.
  - E2's APKAM key is a distinct, individually-revocable record.

## 1.3 Second host on the *same* enrollment — UC-A2.2

- **Given:** `@alice` pq-native; `alice1` on E1; the E1 keyfile is copied to a second host (`alice1b`).
- **When:** `alice1b` first runs.
- **Steps:**
  1. `alice1b` authenticates (it has E1's existing APKAM private from the copied keyfile).
  2. Mint-once per APKAM keypair: the copied keyfile may already carry a PQ APKAM keypair (then
     reuse) or not (then mint a **new** PQ APKAM keypair and register an immutable per-APKAM
     enrollment record under E1).
  3. Obtain `pqpublickey@alice⁻¹` — present in the copied keyfile, else `requestSecret`.
  4. Register `alice1b`'s X-Wing key package in its per-APKAM enrollment record (not published).
- **Then:**
  - If the second host minted its own APKAM keypair (the keyfile copy predated alice1's upgrade),
    E1 now has **two** PQ APKAM keypairs (individually revocable); if it inherited the keypair from
    the copied keyfile, E1 has **one** shared across both hosts.
  - Both hosts share `pqpublickey@alice⁻¹` and E1's namespace authorisations.
  - **Decision (PQ APKAM placement):** the PQ APKAM private lives in the **copyable keyfile**
    section, so a copy made *after* upgrade inherits/shares it — revocation is per-keyfile-key,
    not strictly per-device. Device-local/keychain is optional hardening for true host
    binding.

## 1.4 Namespace-restricted enrollment — UC-A2.3

- **Given:** `@alice` pq-native; `alice1` (E1, `*`) approves `alice3` for `[app_1.my_apps]` only (E3).
- **When:** `alice3` enrolls (as 1.2).
- **Then:** `alice3.pqpk⁻¹ = ✓` (root, universal); `alice3` receives `nskey.app_1.my_apps@alice⁻¹` only; a
  `requestSecret` for `app_2.my_apps` is refused (namespace = authz boundary); `alice3` can read/write
  `app_1.my_apps` data but not `app_2.my_apps`.

---

# 2. Upgrade paths (existing pre-PQ atSign)

Start state: `@alice = legacy` (RSA `publickey`, RSA APKAM per enrollment), `aliceS = pq`,
no `pqpublickey`.

## 2.0 atServer upgrade is a prerequisite — UC-B0.1

- **Given:** `aliceS = legacy`; `alice1` is a PQ-capable build.
- **When:** `alice1` attempts the upgrade sequence (2.1).
- **Then:** the new PQ verbs (PQ-APKAM-auth / multiple-APKAM / delete-pubkey / eviction) are
  unavailable → `alice1` aborts the upgrade cleanly, **stays legacy**, mints no PQ keys, logs
  why. No partial state on the server. (The atServer's immutable write is long-standing and
  present even here — it is *not* a PQ-only verb.)

## 2.1 First client upgrade — UC-B1.1

- **Given:** above; `alice1` on E1 with the legacy RSA APKAM key; `pqpublickey` absent.
- **When:** `alice1` runs the upgrade.
- **Steps:**
  1. Authenticate legacy (RSA APKAM).
  2. **Mint-once per APKAM keypair** a PQ APKAM keypair; register its immutable per-APKAM
     enrollment record for E1.
  3. **Verify** PQ APKAM auth succeeds.
  4. **Delete** the legacy RSA APKAM pubkey for E1 (only after step 3).
  5. Persist AtKeys; register this APKAM keypair's X-Wing key package in its per-APKAM enrollment
     record (not published).
  6. **Immutable-create** `public:pqpublickey@alice` → **wins** → generate X-Wing keypair, hold
     `pqpublickey@alice⁻¹`, seed `pqid:<kid>`, serve on request.
  7. When the roster holds the key, flip readiness (or leave `n-r` until siblings upgrade).
- **Then:**
  - `alice1.APKAM = pq`; legacy RSA APKAM pubkey **gone**; PQ auth works.
  - `public:pqpublickey@alice` created; `alice1.pqpk⁻¹ = ✓`; `alice1` serves the private on request.
  - Legacy *encryption* key retained (history still readable). No re-onboarding.

## 2.2 Second client, same enrollment — UC-B1.2

- **Given:** after 2.1; `pqpublickey` exists; `alice2` on E1 (RSA APKAM).
- **When:** `alice2` runs the upgrade.
- **Steps:** 1–5 as 2.1 (mints its **own** PQ APKAM, registers its per-APKAM record, verifies,
  deletes *its* legacy view if applicable, persists, registers its X-Wing key package in its
  per-APKAM enrollment record). Step 6: **immutable-create rejected (exists)** →
  `requestSecret(pqid:<kid>)` → verify public/private correspondence → store.
- **Then:** `alice2.APKAM = pq`, `pqpk⁻¹ = ✓`; it never created or overwrote `pqpublickey`; E1
  now has two PQ APKAM keypairs.

## 2.3 Third client, different enrollment — UC-B1.3

- **Given:** after 2.1; `alice3` on E2 (its own legacy RSA APKAM).
- **When:** `alice3` runs the upgrade.
- **Then:** identical to 2.2 for the bootstrap (own PQ APKAM, request `pqpublickey@alice⁻¹`). For
  **namespaced** secrets, a restricted E2 receives only its authorised `nskey` keys.

## 2.4 Legacy APKAM deletion & lockout — UC-B2.1 / B2.2

- **Given:** E1 keyfile copied to `alice1b` (un-upgraded); `alice1` upgraded and deleted E1's
  legacy APKAM pubkey.
- **When:** `alice1b` authenticates (legacy).
- **Then (default, immediate delete):** auth **fails** (pubkey gone) → `alice1b` must re-enroll.
  This is the intended enforcement.
- **Then (grace-period knob):** legacy auth succeeds for N days; `alice1b` may upgrade in the
  window; after expiry the legacy pubkey auto-deletes and the default applies. (Bypass open
  during the window — explicit trade-off.)

---

# 3. E2EE within one atSign (self) — puts & notifications

## 3.1 Self put, namespace key exists — UC-A3.1

- **Given:** `@alice` pq-native; `public:nskey.app_1.my_apps@alice` published; `alice1`, `alice2` hold `nskey.app_1.my_apps@alice⁻¹`.
- **When:** `alice1` does `put <k>.app_1.my_apps@alice` (shouldEncrypt).
- **Steps:**
  1. Cut a symmetric **content key (CK)**; encrypt the value with it (AES-256-GCM under the CK).
  2. **Convey the CK once** (`at/nskey`): X-Wing-seal the CK to @alice's **self nskey** (the
     unpublished one) and write it as its own CK-conveyance record, cited by `ckKid`. (Skip if the
     CK is already conveyed.)
  3. Write the **data** value (`at/symmetric/AES/GCM`): stamp `appMetadata.providerId =
     at/symmetric/AES/GCM`, `ckKid`, `iv`; the value carries **no** inline sealed CK. Write; sync.
- **Then:**
  - `alice2` syncs both records: the `at/nskey` provider decapsulates the CK with the self-nskey
    private and caches it by `ckKid`; the `at/symmetric/AES/GCM` provider resolves the CK by `ckKid`
    and AES-GCM-decrypts the value.
  - No legacy provider, no `selfEncryptionKey` used.
  - Acceptance test: round-trip equals plaintext; data value `providerId = at/symmetric/AES/GCM`
    citing `ckKid`; a client lacking the self-nskey private cannot decapsulate the CK and so cannot
    read.

## 3.2 First self put in a namespace mints + distributes both `nskey.app_1.my_apps@alice` keypairs — UC-A3.2

- **Given:** `@alice` pq-native; **no** `nskey.app_1.my_apps@alice` yet; `alice1`, `alice2` PQ, both
  with registered X-Wing key packages.
- **When:** `alice1` does the first `put <k>.app_1.my_apps@alice`.
- **Steps:**
  1. `alice1` mints **both** `app_1.my_apps` nskey X-Wing keypairs: the **self nskey** (the
     unpublished `nskey.app_1.my_apps@alice`, to which alice encapsulates her own CKs) **and** the
     **public nskey** (**immutable-create** `public:nskey.app_1.my_apps@alice`, to which external
     senders encapsulate). `alice1` holds both privates and seeds each as
     `Secret(namespace: app_1.my_apps, name: nskey:<kid>, value: <private>)` for substrate delivery
     (working names; the canonical delivery shape is `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice`).
  2. Convey the CK once via the **nskey data path** (as 3.1): cut a CK, seal it to the self nskey
     in an `at/nskey` record, write the data under `at/symmetric/AES/GCM`.
  3. The two nskey privates are **pushed** per-APKAM to every authorised member: `alice1` calls
     `enroll:listfornamespace:app_1.my_apps`, then `pqSeal`s each private to `alice2`'s X-Wing key
     package (addressed by `kpid`) and delivers on `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice`.
     `alice2` verifies correspondence against `public:nskey.app_1.my_apps@alice` and `putIfNewer`s.
     (`requestSecret` is the offline pull backstop if `alice2` missed the push.)
- **Then:**
  - `public:nskey.app_1.my_apps@alice` published once (immutable); the self nskey stays unpublished;
    `alice2` obtains **both** privates and can read.
  - An `app_2.my_apps`-only client is refused the `app_1.my_apps` nskey privates (namespace = authz
    boundary, server-gated on the `__ssenv` channel).

## 3.3 Self put falls back to `pqpublickey` (no namespace key) — UC-A3.3

- **Given:** `@alice` pq-native; no `public:nskey.app_1.my_apps@alice`; "seal-and-hold" **not** selected (send-now is the default; seal-and-hold is the per-namespace opt-in).
- **When:** `alice1` writes self data before any namespace key exists.
- **Then:** the **CK** is X-Wing-sealed to `public:pqpublickey@alice` (root) via an `at/nskey`
  conveyance record (`recipientKind: root-pqpublickey`) — data is **never** encrypted directly to
  the root key; the data value stays `at/symmetric/AES/GCM` citing `ckKid`. Any `@alice` client
  decapsulates the CK with the root private and decrypts. Self-heals to the namespace's public/self
  nskey on the first namespaced write.

## 3.4 Self notification — NEW

- **Given:** `@alice` pq-native; `alice1`, `alice2` PQ; `alice2` running a monitor.
- **When:** `alice1` does `notify` to `@alice` (self) carrying an encrypted value (e.g. an
  `update`/`delete` notification with `value` + shouldEncrypt).
- **Steps:**
  1. Encrypt the notification value exactly as a self put: AES-256-GCM under a CK
     (`at/symmetric/AES/GCM`, cited by `ckKid`); the CK is conveyed once via an `at/nskey` record
     sealed to the **self nskey** (or `pqpublickey` cold-start).
  2. Stamp `appMetadata.providerId` on the **notification** payload; send `notify:`.
  3. atServer queues/delivers; `alice2`'s monitor receives the notification frame.
  4. `alice2` reads `providerId` from the notification, decapsulates, decrypts the value.
- **Then:**
  - The notification's value decrypts on `alice2` with the same provider routing as a put.
  - `providerId` travels **on the notification**, not only on stored keys (notification framing
    must carry `appMetadata`).
  - Offline `alice2`: the queued notification still decrypts on later delivery (key still held).
  - Acceptance test: a self-notification with an encrypted value round-trips on a sibling;
    a notification with no value (signal-only) needs no decryption and is unaffected.

## 3.5 Mixed — upgraded `alice1`, un-upgraded `alice2` — UC-B3.1

- **Given:** `alice1` PQ; `alice2` legacy-only; `@alice` readiness `n-r`.
- **When:** `alice1` puts/notifies self data both must read.
- **Then:** `alice1` writes/notifies **legacy** (the scheme `alice2` can read) until readiness
  flips; `alice2` reads via the legacy provider; no self data is unreadable by `alice2`. After
  all `@alice` clients are PQ and readiness flips `ready`, new self puts/notifications use the
  **nskey data path** (UC-B3.2).

---

# 4. E2EE across atSigns — shares & notifications

## 4.1 Shared put, recipient has the namespace key — UC-A4.1

- **Given:** `@alice`, `@bob` pq-native; `@bob` published `public:nskey.app_1.my_apps@bob`; `bob1`,`bob2` hold
  `nskey.app_1.my_apps@bob⁻¹`; `@bob` readiness `ready`.
- **When:** `alice1` does `put @bob:<k>.app_1.my_apps@alice` (shouldEncrypt).
- **Steps:**
  1. Cut a symmetric **CK**; encrypt the value with it (AES-256-GCM under the CK).
  2. **Convey the CK once** (`at/nskey`): X-Wing-seal the CK to **bob's** published public nskey
     `public:nskey.app_1.my_apps@bob` (fetched from `@bob`), as a discrete CK-conveyance record
     cited by `ckKid`.
  3. Write the **data** value (`at/symmetric/AES/GCM`, citing `ckKid`); sync (delivered to `@bob`).
  4. Write the **self-copy** for alice's own clients: convey the CK once via an `at/nskey` record
     sealed to **alice's self nskey** (the unpublished one, **not** her published public nskey),
     plus the data value under `at/symmetric/AES/GCM`.
- **Then:**
  - `bob1` and `bob2` decapsulate the CK with their **public-nskey private** and read; `alice`'s
    clients decapsulate the self-copy's CK with the **self-nskey private** and read.
  - PQ end to end; data values `providerId = at/symmetric/AES/GCM`, CK conveyances `at/nskey`; no
    RSA on any path.
  - Acceptance: every authorised reader on both atSigns decrypts; an unauthorised `@bob`
    enrollment cannot fetch the ciphertext (server-gated) nor decrypt.

## 4.2 Shared put cold-start → `pqpublickey` fallback — UC-A4.2

- **Given:** `@alice`, `@bob` pq-native; `@bob` has `public:pqpublickey@bob` but **no** `public:nskey.app_1.my_apps@bob`.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Steps:** as 4.1 but X-Wing-seal the **CK** to **bob's `public:pqpublickey@bob`** (root fallback)
  in the `at/nskey` conveyance record (`recipientKind: root-pqpublickey`) — only the CK is sealed
  to the root; the data value stays `at/symmetric/AES/GCM`. Mark the fallback in `appMetadata`.
- **Then:** every bob client reads instantly (all hold `pqpublickey@bob⁻¹`); when a bob `app_1.my_apps` client
  later publishes `public:nskey.app_1.my_apps@bob`, subsequent writes **upgrade** to the namespace key. (High-security
  `app_1.my_apps` may instead seal-and-hold — the per-namespace opt-in.)

## 4.3 Cross-atSign notification — NEW

- **Given:** `@alice`, `@bob` pq-native; `@bob` published `public:nskey.app_1.my_apps@bob` (or `public:pqpublickey@bob` fallback);
  `@bob` readiness `ready`; `bob1` running a monitor.
- **When:** `alice1` `notify`s `@bob` with an encrypted value (e.g. share a key + notify).
- **Steps:**
  1. Encrypt the notification value under a CK (`at/symmetric/AES/GCM`, cited by `ckKid`); convey
     the CK once via an `at/nskey` record X-Wing-sealed to bob's published public nskey
     `public:nskey.app_1.my_apps@bob` (or `public:pqpublickey@bob` cold-start) — same CK→nskey
     conveyance as 4.1/4.2.
  2. Stamp `appMetadata.providerId` on the notification; `notify:@bob…`.
  3. `bobS` queues; on `bob1` reconnect the monitor delivers the notification frame.
  4. `bob1` routes by `providerId`, decapsulates, decrypts; `bob2` likewise on its monitor.
- **Then:**
  - The notification value decrypts on every authorised bob client with the same routing as a
    shared put.
  - Negotiation gates the notification's scheme on **bob's** readiness (a legacy bob → legacy
    notification — UC-B4.1).
  - Offline-then-online bob still decrypts the queued notification (key held; or pulled if the
    key arrived meanwhile).
  - Acceptance: encrypted-value notification round-trips across atSigns to all authorised bob
    clients; signal-only notifications are unaffected; `appMetadata` is present on the
    notification frame (not only on stored keys).

## 4.4 Mixed PQ/legacy across atSigns — UC-B4.1 / B4.3 / B4.4

- **B4.1 — `@alice` PQ-ready, `@bob` legacy.** `alice1` shares/notifies `@bob`: writes **legacy**
  (RSA-wrapped CK + AES) to bob's `publickey` (bob's readiness `n-r` gates it); alice's self-copy
  may take the **nskey data path** independently. **Then:** no write/notification bob can't read;
  alice's own clients still get an nskey-data-path self-copy if all alice clients are PQ.
- **B4.3 — partially-upgraded `@alice` (alice1 PQ, alice2 legacy) → `@bob` PQ-ready.** The write
  to `@bob` may take the **nskey data path** (bob ready), but alice's **self-copy** is legacy
  (alice2 can't read PQ) until `@alice` readiness flips. **Then:** two directions, two schemes,
  one `put`/`notify`.
- **B4.4 — `@bob` finishes upgrading.** Once all bob clients PQ and bob readiness `ready`,
  alice's next share/notify to `@bob` takes the **nskey data path**. **Then:** legacy path no
  longer used toward bob.

---

## Cross-cutting acceptance (applies to all flows)

- **Reads are universal:** a client decrypts anything ever written to it (all providers retained);
  upgrading only ever adds read-capability.
- **Writes gated by reader readiness:** a value/notification is only written in a scheme **every**
  required reader supports; otherwise legacy (3.x) or refused (`disallowLegacyEncryption=true`).
- **`appMetadata.providerId` is authoritative** and present on **both** stored keys and
  **notification frames**.
- **No RSA in any confidentiality path** for a fully-PQ interaction (auth, enrollment conveyance,
  self, shared, notification).
- **Immutability:** `pqpublickey` and namespace public keys are create-once; a second create is
  rejected, never an overwrite.

## Decisions (see catalogue)

Resolved 2026-06-24 (full text in the catalogue's *Decisions* section):
1. Legacy-peer interop (1.1, 4.4) — **config flag, default off** (PQ-only by default).
2. Readiness granularity (3.5, 4.x) — **per (atSign, namespace)** (+ atSign-level root).
3. PQ APKAM placement (1.3, 2.x) — **copyable keyfile** (a copy after upgrade shares it).
4. `nskey` to a new enrollment (1.2, 3.2) — **push at approve + pull fallback**.
5. Seal-and-hold vs send-now (3.3, 4.2) — **send-now default; per-namespace seal-and-hold opt-in**.
