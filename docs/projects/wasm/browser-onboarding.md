# Browser onboarding — problem definition and solution flow

**Status:** model decided 2026-10-15 as K-1..K-9, storage layout re-ruled 2026-10-27 as K-10 (pointer) and K-11 (document) in [`decisions.md`](decisions.md); K-6 and K-8 superseded; K-5 re-ruled and K-12 (passkey-derived PKAM key) ruled 2026-10-27 · derivation in [atkeys-derivation.md](atkeys-derivation.md) · build not started (bd `5vf.1`–`5vf.7`); open: Q-3 (portal envelope), Q-4, Q-5, Q-6 (K-12 fallbacks)
**Supersedes:** the shared `public:_atkeys.<app>@<atSign>` server copy with an `unlocks[]` array (PB-5 H/J, live-tested in L step 0a)
**Resolves:** OQ-19 (prf unlocks accumulate on the server copy)

---

## 1. Problem

An app client running in a browser must:

| # | Requirement |
|---|---|
| R1 | Hold the atSign's @keys without them ever being stored in plaintext in the browser |
| R2 | Reopen on the same browser with one biometric/PIN prompt and no passphrase |
| R3 | Recover after browser storage is cleared, with the passkey alone — no passphrase, no typing. Met on the primary path because the PKAM key is derived from the passkey (K-12); the fallbacks are open (Q-6) |
| R4 | Not let a compromised atServer decrypt the stored keys |
| R5 | Not let an outside reader learn how many devices an atSign has, or link a record to a passkey |
| R6 | Not accumulate records for passkeys that no longer exist (under K-10, bounded: at most one orphan pointer per passkey, §5) |
| R7 | Sign with the strongest algorithm the browser offers today and pick up ML-DSA without a format change |

### What the live test found (L step 0a, 2026-10-11)

| Finding | Requirement broken |
|---|---|
| Every new passkey appends a prf unlock to one shared public record; nothing removes dead ones (the browser cannot enumerate passkeys) | R6 |
| The record is a public key looked up by atSign — anyone can count the unlocks | R5 |
| Each device's local copy carries every unlock and is merged back into the server copy, so a stale device re-adds entries that were removed | R6 |

---

## 2. Model

**One public pointer per passkey** (K-10), stored under a lookup key that only that passkey can derive, naming **one private document per enrollment** (K-11) that holds the sealed @keys.

| Element | Value |
|---|---|
| PRF salt | **constant** per RP: `SHA-256("atsign:keys:lookup:v1")` — see BO-2 |
| PRF output `P` | one WebAuthn `get()` with `prf.eval.first = salt` |
| Lookup key | `HKDF-SHA256(P, salt = ∅, info = "atkeys-record-id\|<atSign>")`, 64 lowercase hex |
| Blob key (kek) | `HKDF-SHA256(P, salt = ∅, info = "atkeys-kek\|<atSign>")` — no stored salt (BO-1) |
| Codec | `{ v: 2, typ, alg: "A256GCM", kdf: "HKDF-SHA256", iv, ct }`, AAD = canonical JSON of the record without `ct` — **no atSign, no credential ID**. `typ` is `"eid"` (pointer) or `"atkeys"` (document) |
| Pointer (K-10) | `public:_<lookupHex>.atkeysv@<atSign>`, plaintext = the `enrollmentId`. **No TTL and no `ttr`**, written once at enroll by an enrollment holding `atkeysv:rw` (`update:public:…`). Read: unauthenticated `lookup:_<lookupHex>.atkeysv@<atSign>` on the atSign's own atServer; miss → `AT0015` or `data:null`. The leading `_` keeps it out of every scan, `showhidden` included, and out of the commit log; because it has no `ttr`, `plookup` from another atServer leaves no cached copy (any other `ttr` would make it cache one). Existing verbs, no server change (at_server trunk `acd5a4ba`) |
| Document (K-11) | `atkeys.<enrollmentId>.a.__e@<atSign>`, private, plaintext = the @keys JSON **without the APKAM private key**. Read and written over PKAM (`llookup:` / `update:`) by that enrollment only; opening it needs the kek, no private key. CRAM can read it but not write it. Not `_`-prefixed, so own-enrollment and CRAM scans list it. Probed P9, 2026-10-20 |
| Passkey `user.id` | the atSign (UTF-8, ≤ 64 bytes) — returned as `userHandle` on every assertion |
| IndexedDB | credential-ID hint (for `allowCredentials`); whether a document replica is also kept is not ruled |
| APKAM key for PKAM | not stored anywhere (K-11, K-12). **Derived from the passkey**: `authSeed = HKDF-SHA256(P, salt = ∅, info = "at_auth/custody/auth-seed/v1\|<atSign>")` seeds an ML-DSA-65 key — the primary path (K-12). Fallbacks open, not ruled (Q-6) |

### Bootstrap sources (how the first @keys arrive on a device)

| Source | When |
|---|---|
| APKAM enrollment from the browser, once per onboarding — **each enrollment has exactly one live passkey** (rotation moves it to a new one), requesting the app's namespaces + `atkeysv:rw`. An OTP admits the request, and it must be minted covering the app namespaces + `atkeysv:rw`: a narrower OTP is spent and the request refused (`UnAuthorizedException`, EVH:341-349); it stays **pending** until an approver acts from an existing device (an OTP never approves). The APKAM key is derived from the passkey (K-12) | **primary** |
| Passphrase envelope cut by the portal (R-5) — written only by a cut, never by a browser | secondary, for a user with no device to approve from (open) |

Both converge on the same pointer + document pair — unproven for the portal source under K-11, which has no enrollment to own a document (open, [`decisions.md`](decisions.md) "Open against K").

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
    B->>A: create(user.id = atSign, residentKey + UV required, prf)
    A-->>B: credential ID (+ prf result, if the platform returns it at create)
    opt create returned no prf result
        B->>A: get(allowCredentials = [id], prf.eval.first = salt)
        A-->>B: P
    end
    B->>B: lookup = HKDF(P,"atkeys-record-id|atSign"); kek = HKDF(P,"atkeys-kek|atSign")
    B->>B: apkamKey = ML-DSA-65(seed = HKDF(P,"at_auth/custody/auth-seed/v1|atSign")), never stored
    B->>S: enroll:request (namespaces + atkeysv:rw, OTP minted for both) → pending until approved
    B->>S: PKAM auth as the approved enrollment; keys:get
    B->>S: update atkeys.eid.a.__e (typ "atkeys": @keys without APKAM private key)
    B->>S: update public:_lookupHex.atkeysv (typ "eid": enrollmentId), no TTL, no ttr, once
    B->>B: IndexedDB: credential-ID hint
```

The APKAM key used for `enroll:request` and PKAM is derived from the passkey (K-12) and re-derived on every open; return (3.2) and recovery (3.3) derive it from the same `P` that yields the kek.

### 3.2 Return — same browser

```mermaid
sequenceDiagram
    participant B as Browser
    participant A as Authenticator
    participant S as atServer
    B->>A: get(allowCredentials = [hint], prf.eval.first = salt)
    A-->>B: P, userHandle = atSign
    B->>S: lookup pointer (unauthenticated) → unseal enrollmentId
    B->>S: PKAM auth as enrollmentId (APKAM key derived from P, K-12)
    B->>S: llookup atkeys.eid.a.__e → open with kek
    B->>S: lookup public:publickey@atSign
    B->>B: restored public keys must match the published ones, else hard fail (BO-9, K-5)
    B->>B: only then use the @keys; rewrite hint; storage.persist() once
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
    S-->>B: pointer → unseal enrollmentId with kek
    B->>S: PKAM auth as enrollmentId (APKAM key derived from P, K-12)
    B->>S: llookup atkeys.eid.a.__e → open with kek
    B->>S: lookup public:publickey@atSign
    B->>B: restored public keys must match the published ones, else hard fail (BO-9, K-5)
    B->>B: only then use the @keys; store hint in IndexedDB
```

Return and recovery differ only in the credential hint: the server holds everything else and the passkey re-derives the PKAM key (K-12), so on the primary path a cleared browser loses nothing. The fallbacks are open (Q-6).

### 3.4 Lifecycle

| Event | Action |
|---|---|
| Rotation | enroll a new passkey (3.1) → confirm it opens → PKAM-authenticated delete of the old pointer → `PublicKeyCredential.signalUnknownCredential` for the old ID where supported (Chrome/Edge 132+, Safari 26; not Firefox) — a hint to the password manager; a page cannot delete passkeys. A new passkey derives a new APKAM key (K-12); the rotation flow itself is proposed, not ruled |
| Browser storage eviction | loses only the credential hint; the recovery flow (3.3) needs none, costing one extra passkey tap. Holds on the K-12 primary path; the fallbacks are open (Q-6) |
| Lost or wiped device | revoke its enrollment: its PKAM is refused (`AT0027`) and its document becomes unreadable (`.r.__e`). The pointer stays (the revoker cannot derive its name) — at most one orphan per passkey. Do not unrevoke it afterwards: unrevoke reinstates the stored public key, so whoever holds the device's private key could PKAM again (policy note, [`decisions.md`](decisions.md)) |
| Revoked enrollment | revocation is final as approver policy ([`decisions.md`](decisions.md), 2026-10-21/27). To re-enroll, the approver **reinstates** it with `enroll:unrevoke`: same `enrollmentId`, same public key, original expiry (expired → `AT0028`); PKAM succeeds again and the document returns. Revoke also revokes every enrollment the revoked one approved; unrevoke does not reinstate those, and unrevoke of one of them is refused while its approver stays revoked, unless that approver was deleted. A new request with the same key is refused with `AT0032` (intended). Revoked with only the passkey is locked out by design |
| Portal re-cut | rotates the passphrase envelope; each enrollment's document keeps working until that enrollment is revoked |

---

## 4. Decisions

> **Numbering.** These `BO-n` are local to this doc, prefixed so they cannot be read as the `decisions.md` D-n of the same number. The binding ledger is `decisions.md` K-1..K-12: local BO-1 → K-2 (and K-3), BO-2 → K-1, BO-4 → K-8 (superseded by K-11), BO-5 → K-8 (survives), BO-6 → K-6 (superseded by K-10), BO-7 → K-10 and K-11, BO-9 → K-4 and K-5. BO-3 and BO-8 are design choices without a K ruling. K-12 (passkey-derived PKAM key) has no local BO; see §2 and Q-6.

| # | Decision | Why |
|---|---|---|
| BO-1 | **One PRF evaluation, two HKDF derivations** (lookup, kek); **no stored salt** | a stored random salt is server-controlled: as a PRF input it lets the server make the blob key equal the lookup key it already knows (key substitution), and costs a second prompt; as an HKDF salt it adds nothing to a 256-bit PRF output. Labels carry the atSign |
| BO-2 | **PRF salt is constant, not derived from the atSign** (changes Gary's model) | `get()` runs locally before any network call; the atSign it returns in `userHandle` then drives root lookup, `lookup:` and `from:`. The salt must be in the request, so it can't depend on the atSign; PRF output is already unique per credential |
| BO-3 | **atSign in `user.id`** | the only per-passkey storage that survives a cleared browser and needs no extra ceremony; makes R3 typing-free |
| BO-4 | ~~APKAM private key inside the blob~~ **superseded 2026-10-27 by K-11** (the document holds no APKAM private key). Was: for the session, imported non-extractable into WebCrypto when WebCrypto supports its algorithm, otherwise held in Dart memory | a non-extractable key persisted by the browser lives in IndexedDB and dies with it — R3 would require re-enrollment |
| BO-5 | **Signing algorithm = first of `SigningAlgoType.strongestFirst` the browser lane can sign with and the atServer verifies**; recorded with the enrollment (`signingAlgo`) | crypto agility already exists in at_chops. The browser makes the choice at enrollment, among algorithms whose keygen finishes within a UI time budget. On the primary path K-12 fixes the APKAM key to ML-DSA-65, derived from the passkey; this choice applies to the fallbacks, which are open (Q-6). The APKAM key is a software key, so the authenticator's algorithm menu does not constrain it — at_chops' default barrel already exports a pure-Dart `mldsa65` signer (Q-4) |
| BO-6 | ~~`ttl` refreshed on open prunes dead passkeys~~ **superseded 2026-10-27 by K-10**: the pointer has no TTL | — |
| BO-7 | **Pointer read by exact lookup key, unauthenticated; document read over PKAM; all writes PKAM-authenticated**; the pointer never appears in `scan` | recovery must find the `enrollmentId` before auth; writes need an owner; enumeration would break R5. The document is listed to its own enrollment and to CRAM only, by an `enrollmentId` they already know |
| BO-8 | A record is **per passkey, not per device**; synced passkeys allowed | iCloud Keychain / Google Password Manager sync one credential across a user's devices. This passkey only unlocks the keys blob — it is not the device-bound credential `trusted-devices/design.md` requires for device-trust assertions |
| BO-9 | **Restored public keys must match the published ones before the restored keys are used** — after PKAM, before any encrypt or decrypt; a mismatch is a hard fail (K-5, re-ruled 2026-10-27); AAD = the record's clear header | the server cannot forge a record without the kek, but it can replay an older valid one (rollback) or edit the clear header (downgrade). The match catches only a partial rollback: the published keys come from the same atServer (§5) |

---

## 5. Security properties

| Property | Holds because |
|---|---|
| A compromised atServer cannot decrypt @keys | the kek needs `P`, which needs the passkey plus platform authentication |
| An outside reader cannot read the @keys | the document is private and read only after PKAM (K-11); unauthenticated readers see at most a pointer's ciphertext, by its exact 256-bit name |
| An outside reader cannot count devices or link a pointer to an atSign's passkeys | lookup keys are PRF-derived and pointers are hidden from every scan (BO-7); pointers carry no atSign or credential ID |
| The passkey private key never leaves the authenticator | WebAuthn |
| Dead passkeys accumulate at most one orphan pointer each | the pointer has no TTL and revocation cannot remove it (K-10); it holds only a sealed `enrollmentId` |
| A stale device cannot resurrect removed records | no shared record, nothing merged |
| A replayed older document is refused when the published keys were not rolled back with it (partial rollback) | BO-9 / K-5 public-key check, after PKAM and before the restored keys are used |

**Does not hold:**

- An atServer can still see that *some* record was read on the atSign's own server — the lookup arrives over a connection to that atSign.
- Any enrollment holding `atkeysv:rw` can overwrite or delete another passkey's pointer **if it knows that pointer's lookup key** (probe P4). The key is PRF-derived and never listed, so this is bounded to a party that already saw it; the effect is denial of recovery, not disclosure. Owner-binding guard deferred (`at_client_sdk-m0j`).
- CRAM can read every enrollment's document; it is still sealed under the kek.
- A compromised atServer that rolls back the document **and** `public:publickey@<atSign>` together passes the K-5 check: the published keys come from the same server. K-5 defends partial rollback only.
- A stale-but-valid document whose public keys are unchanged (other @keys state older) passes the K-5 check — acknowledged limit.
- A server can move a valid document ciphertext to another enrollment's document name under the same kek; binding the `enrollmentId` and record name into the AAD is a proposed follow-up ([`decisions.md`](decisions.md)), not ruled.

---

## 6. Open questions

| # | Question | Owner |
|---|---|---|
| Q-1 | ~~`T` — record ttl~~ — **withdrawn 2026-10-27:** the K-10 pointer has no TTL | — |
| Q-2 | ~~at-keys module grammar on the atServer~~ — **resolved 2026-10-15:** existing `update`/`lookup`/`delete` on `public:_<lookupHex>.atkeysv@<atSign>`, no server change (probe P1–P7); kept by K-10 (§2 Pointer row) | — |
| Q-3 | ~~Bootstrap via APKAM enrollment~~ — **resolved 2026-10-13:** the browser enrolls, one enrollment per passkey; open: whether the portal envelope stays as a secondary bootstrap | me + Gary |
| Q-4 | Which of `mldsa65` / `rsa4096` / `ed25519` / `ecc_secp256r1` the browser lane signs with today (pure Dart under dart2js/dart2wasm, or WebCrypto via #2265) and the atServer verifies for PKAM — sets BO-5's current pick | me (probe) |
| Q-5 | Which platforms return PRF results from `create()` — decides whether enrollment is one prompt or two | me (probe) |
| Q-6 | **K-12 fallbacks — open, not ruled.** The PKAM key when the passkey path cannot run: (a) an authenticator without PRF; (b) a lost or wiped passkey; (c) an IndexedDB-held APKAM key as a fallback that does not survive a cleared browser; (d) a second registered passkey | me |
