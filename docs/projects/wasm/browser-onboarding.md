# Browser onboarding — problem definition and solution flow

**Status:** model decided 2026-10-15 as K-1..K-9 in [`decisions.md`](decisions.md) · derivation in [atkeys-derivation.md](atkeys-derivation.md) · build not started (bd `5vf.1`–`5vf.7`); open: Q-1, Q-3 (portal envelope), Q-4, Q-5
**Supersedes:** the shared `public:_atkeys.<app>@<atSign>` server copy with an `unlocks[]` array (PB-5 H/J, live-tested in L step 0a)
**Resolves:** OQ-19 (prf unlocks accumulate on the server copy)

---

## 1. Problem

An app client running in a browser must:

| # | Requirement |
|---|---|
| R1 | Hold the atSign's @keys without them ever being stored in plaintext in the browser |
| R2 | Reopen on the same browser with one biometric/PIN prompt and no passphrase |
| R3 | Recover after browser storage is cleared, with the passkey alone — no passphrase, no typing |
| R4 | Not let a compromised atServer decrypt the stored keys |
| R5 | Not let an outside reader learn how many devices an atSign has, or link a record to a passkey |
| R6 | Not accumulate records for passkeys that no longer exist |
| R7 | Sign with the strongest algorithm the browser offers today and pick up ML-DSA without a format change |

### What the live test found (L step 0a, 2026-10-11)

| Finding | Requirement broken |
|---|---|
| Every new passkey appends a prf unlock to one shared public record; nothing removes dead ones (the browser cannot enumerate passkeys) | R6 |
| The record is a public key looked up by atSign — anyone can count the unlocks | R5 |
| Each device's local copy carries every unlock and is merged back into the server copy, so a stale device re-adds entries that were removed | R6 |

---

## 2. Model

**One encrypted record per passkey**, stored under a lookup key that only that passkey can derive.

| Element | Value |
|---|---|
| PRF salt | **constant** per RP: `SHA-256("atsign:keys:lookup:v1")` — see D-2 |
| PRF output `P` | one WebAuthn `get()` with `prf.eval.first = salt` |
| Lookup key | `HKDF-SHA256(P, salt = ∅, info = "atkeys-record-id\|<atSign>")`, 64 lowercase hex |
| Blob key (kek) | `HKDF-SHA256(P, salt = ∅, info = "atkeys-kek\|<atSign>")` — no stored salt (D-1) |
| Record | `{ v: 2, alg: "A256GCM", kdf: "HKDF-SHA256", iv, ct }`, AAD = canonical JSON of the record without `ct` — **no atSign, no credential ID** |
| Plaintext of `ct` | the full @keys JSON **including the PCAM private key** and its `signingAlgo` |
| Passkey `user.id` | the atSign (UTF-8, ≤ 64 bytes) — returned as `userHandle` on every assertion |
| IndexedDB | credential-ID hint (for `allowCredentials`) + local replica of this passkey's record only |
| Server | existing verbs on a reserved name, no new module (probed on trunk 310aa150, P1–P7): `public:_<lookupHex>.atkeysv@<atSign>`. Read: unauthenticated `lookup:_<lookupHex>.atkeysv@<atSign>` on the atSign's atServer; miss → `AT0015`, expired → `data:null` (both are a miss). Write/refresh: `update:ttl:<T ms>:public:_<lookupHex>.atkeysv@<atSign> <record>` from an enrollment holding `atkeysv:rw`; re-`update` moves `expiresAt`. Delete: `delete:public:_<lookupHex>.atkeysv@<atSign>`. The leading `_` keeps it out of every scan (owner, showhidden, `scan:cl`, APKAM, pol, unauthenticated) and the commit log; `plookup` from another atServer leaves no cached copy |

### Bootstrap sources (how the first @keys arrive on a device)

| Source | When |
|---|---|
| APKAM enrollment from the browser, once per onboarding — **each enrollment has exactly one live passkey** (rotation moves it to a new one), requesting the app's namespaces + `atkeysv:rw`, approved by OTP or from an existing device; the browser generates the PCAM key pair | **primary** |
| Passphrase envelope cut by the portal (R-5) — written only by a cut, never by a browser | secondary, for a user with no device to approve from (open) |

Both converge on the same per-passkey record.

---

## 3. Flows

### 3.1 Enrollment — first visit with a new passkey

```mermaid
sequenceDiagram
    participant U as User
    participant B as Browser (at_client_wasm / wasm)
    participant A as Authenticator / password manager
    participant S as atServer
    U->>B: atSign
    B->>S: bootstrap @keys (passphrase envelope, or APKAM enrollment)
    B->>A: create(user.id = atSign, residentKey + UV required, prf)
    A-->>B: credential ID (+ prf result, if the platform returns it at create)
    opt create returned no prf result
        B->>A: get(allowCredentials = [id], prf.eval.first = salt)
        A-->>B: P
    end
    B->>B: lookup = HKDF(P,"atkeys-record-id|atSign"); kek = HKDF(P,"atkeys-kek|atSign")
    B->>B: ct = AES-256-GCM(kek, random iv, @keys incl. PCAM private key, AAD = header)
    B->>S: PKAM auth, then put(lookup, record, ttl = T)
    B->>B: IndexedDB: credential-ID hint + record
```

### 3.2 Return — same browser

```mermaid
sequenceDiagram
    participant B as Browser
    participant A as Authenticator
    participant S as atServer
    B->>A: get(allowCredentials = [hint], prf.eval.first = salt)
    A-->>B: P, userHandle = atSign
    B->>B: open local record with kek
    B->>S: PKAM auth; refresh ttl on lookup (at most once per day)
```

### 3.3 Recovery — browser storage cleared, passkey kept

```mermaid
sequenceDiagram
    participant B as Browser
    participant A as Authenticator
    participant S as atServer
    B->>A: get(no allowCredentials, prf.eval.first = salt)
    A-->>B: P, userHandle = atSign, credential ID
    B->>S: lookup(HKDF(P,"atkeys-record-id|atSign")) on atSign's atServer — unauthenticated, no from:
    S-->>B: record
    B->>B: open with kek; restored public keys must match the published ones (D-9)
    B->>B: store hint + record in IndexedDB
    B->>S: PKAM auth; refresh ttl
```

### 3.4 Lifecycle

| Event | Action |
|---|---|
| Rotation | enroll a new passkey (3.1) → confirm it opens → PKAM-authenticated delete of the old lookup key → `PublicKeyCredential.signalUnknownCredential` for the old ID where supported (Chrome/Edge 132+, Safari 26; not Firefox) — a hint to the password manager; a page cannot delete passkeys |
| Lost or wiped device | its record stops being refreshed and expires after `T`; revoke its APKAM enrollment if it had its own |
| Portal re-cut | rotates the passphrase envelope; each per-passkey record keeps working until its keys are revoked |

---

## 4. Decisions

> **Numbering.** These `D-n` are local to this doc and collide with the rulings of the same number in `decisions.md`. The binding ledger is `decisions.md` K-1..K-9: local D-1 → K-2 (and K-3), D-2 → K-1, D-4 and D-5 → K-8, D-6 → K-6 (TTL), D-7 → K-6 (grammar), D-9 → K-4 and K-5. D-3 and D-8 are design choices without a K ruling.

| # | Decision | Why |
|---|---|---|
| D-1 | **One PRF evaluation, two HKDF derivations** (lookup, kek); **no stored salt** | a stored random salt is server-controlled: as a PRF input it lets the server make the blob key equal the lookup key it already knows (key substitution), and costs a second prompt; as an HKDF salt it adds nothing to a 256-bit PRF output. Labels carry the atSign |
| D-2 | **PRF salt is constant, not derived from the atSign** (changes Gary's model) | `get()` runs locally before any network call; the atSign it returns in `userHandle` then drives root lookup, `lookup:` and `from:`. The salt must be in the request, so it can't depend on the atSign; PRF output is already unique per credential |
| D-3 | **atSign in `user.id`** | the only per-passkey storage that survives a cleared browser and needs no extra ceremony; makes R3 typing-free |
| D-4 | **PCAM private key inside the blob**; for the session, imported non-extractable into WebCrypto when WebCrypto supports its algorithm, otherwise held in Dart memory | a non-extractable key persisted by the browser lives in IndexedDB and dies with it — R3 would require re-enrollment |
| D-5 | **Signing algorithm = first of `SigningAlgoType.strongestFirst` the browser lane can sign with and the atServer verifies**; recorded in the blob | crypto agility already exists in at_chops. The browser makes the choice at enrollment, among algorithms whose keygen finishes within a UI time budget. The PCAM key is a software key (D-4), so the authenticator's algorithm menu does not constrain it — at_chops' default barrel already exports a pure-Dart `mldsa65` signer, so ML-DSA may be the pick today (Q-4) |
| D-6 | **`ttl` refreshed on open** prunes dead passkeys | the browser cannot learn that a passkey was deleted; expiry needs no one to know (R6) |
| D-7 | **Reads by exact lookup key, unauthenticated; writes PKAM-authenticated**; records never appear in `scan` | recovery must read before auth; writes need an owner; enumeration would break R5 |
| D-8 | A record is **per passkey, not per device**; synced passkeys allowed | iCloud Keychain / Google Password Manager sync one credential across a user's devices. This passkey only unlocks the keys blob — it is not the device-bound credential `trusted-devices/design.md` requires for device-trust assertions |
| D-9 | **Restored public keys must match the published ones before PKAM**; AAD = the record's clear header | the server cannot forge a record without the kek, but it can replay an older valid one (rollback) or edit the clear header (downgrade) |

---

## 5. Security properties

| Property | Holds because |
|---|---|
| A compromised atServer cannot decrypt @keys | the blob key needs `P`, which needs the passkey plus platform authentication |
| An outside reader cannot count devices or link a record to an atSign's passkeys | lookup keys are PRF-derived and records are not enumerable (D-7); records carry no atSign or credential ID |
| The passkey private key never leaves the authenticator | WebAuthn |
| Dead passkeys do not accumulate | D-6 |
| A stale device cannot resurrect removed records | no shared record, nothing merged |
| A replayed older record is refused | D-9 public-key check |

**Does not hold:**

- An atServer can still see that *some* record was read on the atSign's own server — the lookup arrives over a connection to that atSign.
- Any enrollment holding `atkeysv:rw` can overwrite or delete another passkey's record **if it knows that record's lookup key** (probe P4). The key is PRF-derived and never listed, so this is bounded to a party that already saw it. Owner-binding guard deferred (`at_client_sdk-m0j`).

---

## 6. Open questions

| # | Question | Owner |
|---|---|---|
| Q-1 | `T` — record ttl (proposal: 90 days) | product |
| Q-2 | ~~at-keys module grammar on the atServer~~ — **resolved 2026-10-15:** existing `update`/`lookup`/`delete` on `public:_<lookupHex>.atkeysv@<atSign>`, no server change (§2 Server row; probe P1–P7) | — |
| Q-3 | ~~Bootstrap via APKAM enrollment~~ — **resolved 2026-10-13:** the browser enrolls, one enrollment per passkey; open: whether the portal envelope stays as a secondary bootstrap | me + Gary |
| Q-4 | Which of `mldsa65` / `rsa4096` / `ed25519` / `ecc_secp256r1` the browser lane signs with today (pure Dart under dart2js/dart2wasm, or WebCrypto via #2265) and the atServer verifies for PKAM — sets D-5's current pick | me (probe) |
| Q-5 | Which platforms return PRF results from `create()` — decides whether enrollment is one prompt or two | me (probe) |
