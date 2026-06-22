# 6_pq_mls_demo — Architecture

End-to-end post-quantum chat where each side can run **N actors** (devices).
A per-side group ratchet keeps the actors in sync; an external-sender HPKE
mode handles cross-side messaging without the sender knowing how many devices
the recipient has.

This document covers: cryptographic primitives, on-disk state, wire envelope
types, group ratchet operations, and the chat process lifecycle.

---

## Read this first

```
┌─────────────────────────────────────────────────────────────────────┐
│  Two names: alice, bob.                                             │
│  Each name has 1..N actors (devices).                               │
│                                                                     │
│       ┌── alice/device1 ──┐                ┌── bob/phone ────┐      │
│       │  alice/device2     │   ── chat ──   │  bob/laptop     │      │
│       └── ...              ┘                └── ...           ┘      │
│             ↑                                       ↑               │
│         group_alice                            group_bob            │
│       (MLS-shaped)                          (MLS-shaped)            │
│                                                                     │
│  - actors on the same side share a group_secret (rotates on Commit) │
│  - cross-side: external-sender HPKE to peer group's externalHpkePk  │
└─────────────────────────────────────────────────────────────────────┘
```

Everything sits on top of OpenSSL 3.6 via Dart FFI. No third-party crypto.

---

## Crypto primitives (lib/openssl.dart)

| Primitive | Use | Source |
|---|---|---|
| ML-KEM-768 | KEM for HPKE; sealing group_secret + externalSk to each member | OpenSSL FFI (reused from demo 3) |
| ML-DSA-65 | Identity signatures on Commits, Welcomes, ExternalAppMessages | OpenSSL FFI |
| AES-256-GCM | AEAD inside HPKE; in-group AppMessage encryption | OpenSSL FFI |
| HKDF-SHA256 | Derive per-message AppMessage keys from group_secret | OpenSSL FFI |
| HMAC-SHA256 | Available; not currently used (Triple Ratchet would use it) | OpenSSL FFI |
| SHA-256 | Available | OpenSSL FFI |
| RAND_bytes | CSPRNG | OpenSSL FFI |
| HPKE base mode | Hybrid encryption — KEM.encaps → HKDF → AEAD.seal | Built in Dart on top of the above |

**HPKE construction** (lib/openssl.dart `Hpke` class):

```
seal(recipientPk, info, aad, plaintext):
    (kemCt, ss) = ML-KEM-768.Encaps(recipientPk)
    key   = HKDF-SHA256(salt=∅, ikm=ss, info=("key"||\0||info), len=32)
    nonce = HKDF-SHA256(salt=∅, ikm=ss, info=("base_nonce"||\0||info), len=12)
    (ct, tag) = AES-256-GCM.Seal(key, nonce, aad, plaintext)
    return (enc=kemCt, ct, tag)

open(recipientSk, enc, info, aad, ct, tag):
    ss    = ML-KEM-768.Decaps(recipientSk, enc)
    key   = same HKDF derivation
    nonce = same HKDF derivation
    return AES-256-GCM.Open(key, nonce, aad, ct, tag)
```

This is RFC 9180 base mode with ML-KEM-768 substituted for the KEM slot.

---

## Group ratchet (lib/group_ratchet.dart)

### State per actor per group

`OwnGroupState` (in keystore.dart):

| Field | What |
|---|---|
| `groupId` | The name (e.g., "alice") |
| `epoch` | Monotonic counter; advances on every Commit |
| `groupSecret` | 32 B; current epoch's master secret |
| `externalHpkeSk` | ML-KEM SK shared across all current members |
| `externalHpkePk` | matching PK, advertised in the public GroupPublicInfo |
| `members` | list of `MemberDesc { deviceId, mlDsaPk, hpkeKemPk }` |
| `sentByThisDevice` | per-sender msg counter for AppMessages this epoch |

### Operations

| Op | What it does |
|---|---|
| **bootstrap**(groupId) | Fresh `group_secret`, fresh ML-KEM keypair as externalHpke, member list = [self]. Epoch 0. |
| **commit**(additions, removals) | Generate new `group_secret` + new externalHpke keypair. For each member of the new epoch, HPKE-seal `group_secret \|\| externalHpkeSk` → CommitWrap. Build Commit + sign with ML-DSA. Build Welcomes for additions. Returns (Commit, Welcomes, newState). |
| **applyCommit**(current, commit) | Verify ML-DSA signature against signer's pk in current members. Find own wrap. HPKE-open → new `group_secret \|\| externalHpkeSk`. Advance epoch. |
| **applyWelcome**(welcome) | Bootstrap as a new joiner. Verify sig, open the wrap, install full state. |
| **sendApp**(plaintext) | Derive `msg_key = HKDF(groupSecret, info="app\|<senderDevice>\|<msgIdx>")`. AES-256-GCM-seal. |
| **receiveApp**(msg) | Same derivation; AES-256-GCM-open. |
| **sendExternal**(peerInfo, plaintext) | HPKE.seal(peerInfo.externalHpkePk, payload). Sign (enc \|\| ct \|\| tag) with ML-DSA. |
| **receiveExternal**(state, msg) | HPKE.open with own externalHpkeSk. Verify ML-DSA sig (TOFU on first contact). |

### Why ML-KEM for external_*pk* rotation works

`externalHpkeSk` rotates on every Commit. Members of the group all hold the
current SK (delivered via per-member HPKE wraps). A sender outside the group
fetches the GroupPublicInfo record on every send to get the current
`externalHpkePk` — when it changes, the sender re-fetches automatically
because their existing PK doesn't match. Forward secrecy: once an epoch ends,
its `externalHpkeSk` is discarded by every member, so prior ciphertexts
become unrecoverable to anyone who steals only future state.

---

## Wire envelopes (lib/wire.dart)

Four message types, each JSON-encoded as the `value` of an inbox row.

| Type | Used for |
|---|---|
| `AppMessage` | In-group message. AES-256-GCM ciphertext + per-sender msgIdx. |
| `ExternalAppMessage` | Cross-side. HPKE `(enc, ct, tag)` to peer.externalHpkePk + ML-DSA sig. |
| `Commit` | Membership delta. New member list + per-member HPKE wraps of `group_secret \|\| externalHpkeSk` + ML-DSA sig. |
| `Welcome` | For each newly-added device. Same wrap payload, addressed to that device. |
| `JoinRequest` | Broadcast on startup when a new actor sees an existing group. Existing leader replies with Commit + Welcome. |

Plus one public record (in the kv `records` table):

| Record key | Value |
|---|---|
| `bundle.<device>.pqdemo` | `{deviceId, mlDsaPk, hpkeKemPk}` for that actor |
| `group.pqdemo` | `GroupPublicInfo { groupId, epoch, members, externalHpkePk }` — written by any current member |

---

## Transport (lib/atserver.dart + lib/transport.dart)

**SQLite per name.** One file `<name>_store.db` shared by all actors of that
name via WAL mode. Two tables:

```sql
CREATE TABLE records (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE inbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_device TEXT NOT NULL,  -- specific device OR "*" for broadcast
  from_name TEXT NOT NULL,
  from_device TEXT,
  msg_type TEXT NOT NULL,
  value TEXT NOT NULL,
  ts INTEGER NOT NULL,
  consumed_by TEXT NOT NULL DEFAULT '[]'  -- JSON list, set per device that pulled it
);
```

**Transport API:**

| Function | What |
|---|---|
| `put(self, key, value)` | INSERT OR REPLACE into own records |
| `get(self, key)` | SELECT from own records |
| `peekPeer(peerDb, key)` | SELECT from peer's records |
| `notifyDevice(peerDb, target, ...)` | INSERT into peer's inbox |
| `notifyBroadcast(peerDb, ...)` | INSERT with target_device="*" |
| `pollInbox(self, deviceId)` | Pull rows targeting deviceId or "*" that haven't been marked consumed by deviceId. Marks them consumed. |

Broadcast rows have `consumed_by` as a per-device list — every actor reading
the same broadcast row appends its own deviceId before processing.

---

## Chat process lifecycle (bin/chat.dart)

```
Startup:
  1. Load keystore (or generate identity + save).
  2. Open <name>_store.db (WAL mode).
  3. put("bundle.<device>.pqdemo", own identity bundle).
  4. Decide role:
       if ownGroup == null:
         if get("group.pqdemo") exists  → broadcast JoinRequest, wait for Welcome.
         else                            → bootstrap solo group; put("group.pqdemo", ...).
       else                              → resume from ownGroup state.
  5. Open peer's <peer>_store.db; peekPeer("group.pqdemo"); cache peerInfo.

Two async loops:
  - inbox poll (every 500 ms):
        for each row from pollInbox(self, deviceId):
          dispatch by msg_type:
            commit          → applyCommit (skip if signer == self)
            welcome         → applyWelcome (target check)
            app             → receiveApp + print
            external_app    → receiveExternal + TOFU pin signer if new
            join_request    → if we are the lowest-deviceId current member, build Commit+Welcome and broadcast
  - stdin loop:
        each line → sendApp (broadcast to own group inbox)
                  + sendExternal (broadcast to peer's inbox)
```

### Join flow in detail

```
new actor (device_N) starts, sees group.pqdemo already present:
  broadcast JoinRequest { groupId=self.name, fromDevice=device_N, mlDsaPk, hpkeKemPk }

each existing actor receives the JoinRequest:
  if I am the lowest-deviceId current member:
    commit(current, additions=[new member])
       → produces Commit + Welcome for the new device
    broadcast Commit to own inbox (so other current actors advance)
    notifyDevice Welcome target_device=device_N

device_N receives:
  - first the Commit arrives but we have no state → "queued" (no-op)
  - then the Welcome arrives → applyWelcome → ownGroup populated

other current actors receive the Commit:
  applyCommit → epoch advances, new member added
```

### Race avoidance

When multiple existing actors see the same JoinRequest, only **the
lowest-deviceId current member** commits. Others log `defer` and stand down.
Deterministic; no protocol-level conflict resolution needed.

---

## End-to-end message flow (alice/device1 types "hi")

```
1. alice/device1 calls sendApp("hi") → AppMessage {epoch, senderDevice=device1, msgIdx, ct, tag}
2. notifyBroadcast on alice_store.db inbox (target=*)
3. alice/device2 polls alice_store.db inbox → reads AppMessage → receiveApp → prints

4. alice/device1 calls sendExternal(peerInfo=bob's group info, "hi") → ExternalAppMessage
5. notifyBroadcast on bob_store.db inbox (target=*)
6. bob/phone polls bob_store.db inbox → reads ExternalAppMessage
     - HPKE.open with bob/phone's view of externalHpkeSk
     - Verify ML-DSA sig with alice/device1's mlDsaPk
     - TOFU-pin alice/device1's signer pk if first-seen
     - print "<alice/device1> hi"
7. bob/laptop does the same — both bob devices decrypt independently because
   they share externalHpkeSk (delivered to each via their Welcome).
```

Total wire bytes for one alice→bob message reaching ALL N bob devices:
**one** notification (≈ enc 1088B + ct ≈ len(plaintext) + tag 16B + sig 3309B + overhead ≈ **4.5 KB**), regardless of N. Sender does not know N.

---

## Forward secrecy + PCS analysis

| Property | Source |
|---|---|
| FS per-message in app channel | HKDF chain on `group_secret`. Past msg_keys are computed but not stored; can't be recovered without `group_secret`. |
| FS across epochs | `group_secret` rotates on every Commit. Old secret discarded. |
| PCS within a side | Every Commit (Add/Remove/Update) injects fresh randomness — attacker who stole old state can't compute the next epoch's `group_secret`. |
| FS for cross-side messages | `externalHpkeSk` rotates on every Commit alongside `group_secret`. Past ExternalAppMessages remain confidential. |
| PCS for cross-side messages | Same — fresh `externalHpkeSk` per epoch. |

**Caveat for the demo:** there's no automated PCS heartbeat (no `/update`
slash-command yet). PCS fires only when membership actually changes. A
production deployment would issue a self-Update every N messages or M
minutes to keep PCS rolling.

---

## What this demo doesn't do

| Skipped | Why |
|---|---|
| TreeKEM (O(log N) Commit cost) | Flat per-member wraps → O(N). Fine for N ≤ ~10. |
| PSK / external Commits / resumption | Beyond demo scope. |
| Multi-device OOB pairing for first device | TOFU on first bundle publish. |
| Skipped-message-key cache | All app messages processed in epoch order. |
| Real network | SQLite inbox stands in. |
| Layer 2 credential chain | TOFU on signer pks. |
| PQ-safe AEAD migration | AES-256-GCM is already PQ-safe at 128-bit security. |

---

## File map

```
6_pq_mls_demo/
├── bin/
│   ├── chat.dart            # interactive CLI per actor
│   ├── ratchet_test.dart    # in-process ratchet smoke test (15 checks)
│   └── smoke.dart           # FFI smoke test (10 primitives)
├── lib/
│   ├── openssl.dart         # ML-DSA + AES-GCM + HKDF + HMAC + SHA-256 + RAND + HPKE
│   ├── group_ratchet.dart   # GroupRatchet (bootstrap, commit, applyCommit, sendApp, …)
│   ├── keystore.dart        # Identity, OwnGroupState, PeerCache, Keystore
│   ├── wire.dart            # AppMessage, ExternalAppMessage, Commit, Welcome, JoinRequest
│   ├── atserver.dart        # SQLite Store
│   └── transport.dart       # put/get/peekPeer/notifyDevice/notifyBroadcast/pollInbox
├── docs/ARCHITECTURE.md     # this file
├── README.md
└── pubspec.yaml             # ffi + sqlite3 + demo_3 (path dep)
```

ML-KEM-768 FFI lives in `../3_openssl_ffi_and_pqcrypto_package_comparison/lib/ml_kem.dart` and is imported via `package:demo_3/ml_kem.dart`. No duplication.
