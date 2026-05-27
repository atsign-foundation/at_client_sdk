# 5_pq_demo — Architecture

Platform-agnostic two-party PQ chat. Each party is a Dart process holding two on-disk artifacts: a **JSON keystore** (long-lived secrets + ratchet state) and a **SQLite store** (the kv-published bundle + incoming notifications). Peers read from each other's SQLite for bundle discovery and write to each other's SQLite to deliver encrypted messages.

This document describes the modules, the on-disk format, the runtime flow, and the tiebreaker logic for initiator vs responder.

---

## Module map

```
bin/chat.dart           Entry point — wires startup, polling loop, stdin loop.

lib/crypto.dart         Primitive wrappers: X25519, Ed25519, ML-KEM-768,
                        HKDF-SHA256, HMAC-SHA256, AES-256-GCM, hex codec.

lib/wire.dart           WireMessage class — encrypted envelope structure,
                        JSON codec (used as inbox row value).

lib/ratchet.dart        Identity, PeerBundle, RatchetState, PQXDH handshake
                        (initiate + respond), sendMessage, receiveMessage.

lib/keystore.dart       Load / save / generate <name>_keystore.json.
                        Holds Identity + per-peer RatchetState map.

lib/store.dart          SQLite-backed local store. WAL mode enabled so
                        peers can read concurrently with our writes.

lib/transport.dart      put / get / peekPeer / notifyPeer / pollInbox.
                        Operates on Store + a peer's Database handle.
```

---

## On-disk state

### `<name>_keystore.json` (plaintext JSON)

```jsonc
{
  "name": "alice",
  "identity": {
    "ikDhSk":  "<hex>", "ikDhPk":   "<hex>",
    "ikSigSk": "<hex>", "ikSigPk":  "<hex>",
    "spkDhSk": "<hex>", "spkDhPk":  "<hex>",
    "spkKemSk":"<hex>", "spkKemPk": "<hex>",
    "spkSig":  "<hex>"
  },
  "ratchets": {
    "bob": {
      "rootKey":"<hex>", "sendCK":"<hex|null>", "recvCK":"<hex|null>",
      "dhSk":"<hex>", "dhPk":"<hex>", "remoteDhPk":"<hex|null>",
      "kemSk":"<hex>", "kemPk":"<hex>", "remoteKemPk":"<hex|null>",
      "sendN":3, "recvN":2, "msgsSinceKem":1,
      "initMessageSent":true
    }
  }
}
```

### `<name>_store.db` (SQLite)

```sql
CREATE TABLE records (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE inbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_name TEXT NOT NULL,
  value TEXT NOT NULL,
  ts INTEGER NOT NULL,
  consumed INTEGER NOT NULL DEFAULT 0
);
```

`records` holds the party's published material. The only key currently used:

- `prekeyBundle` → JSON value `{name, ikDhPk, ikSigPk, spkDhPk, spkKemPk, spkSig}`

`inbox` is a FIFO queue. Peers `INSERT` rows here to deliver encrypted messages. The owning party polls `consumed=0` rows and marks them consumed.

**WAL mode** is enabled (`PRAGMA journal_mode=WAL`) so two processes can read+write the same DB file concurrently without deadlocking.

---

## Transport API

All five operations are local SQL — there is no network code anywhere in the demo.

| Function | SQL action |
|---|---|
| `put(self, k, v)` | `INSERT OR REPLACE INTO self.records (key, value, updated_at) VALUES (?, ?, ?)` |
| `get(self, k)` | `SELECT value FROM self.records WHERE key = ?` |
| `peekPeer(peerDb, k)` | `SELECT value FROM peer.records WHERE key = ?` |
| `notifyPeer(peerDb, from, v)` | `INSERT INTO peer.inbox (from_name, value, ts) VALUES (?, ?, ?)` |
| `pollInbox(self)` | `SELECT * FROM self.inbox WHERE consumed=0 ORDER BY id` + mark consumed |

---

## Crypto stack

| Layer | Purpose | Used during |
|---|---|---|
| Ed25519 | Sign and verify the SPK | Identity gen; bundle verification on lookup |
| X25519 | Classical DH | `dh1`, `dh2`, `dh3` in PQXDH; every DH ratchet step |
| ML-KEM-768 | Post-quantum KEM | `kem_ss` in PQXDH init; KEM ratchet steps |
| HKDF-SHA256 | Mixer | PQXDH init (32B output); every ratchet step (64B output = newRK ‖ newCK) |
| HMAC-SHA256 | Symmetric chain step | `chain_key → msg_key + next chain_key`, every message |
| AES-256-GCM | Bulk encryption | Per-message seal/open |

---

## Flow on startup (per process)

```
1. Load <name>_keystore.json
     if absent → genIdentity(name) → save fresh keystore
2. Open <name>_store.db
     CREATE schema if absent
     PRAGMA journal_mode=WAL  (lets peers read while we write)
3. put('prekeyBundle', JSON.encode(identity.publicBundle()))
4. Wait for <peer>_store.db file to exist; peekPeer until prekeyBundle present
5. PeerBundle.fromJson → verifySignature() with Ed25519
   if invalid → abort
6. Decide role:
     iAmInitiator = self < peer  (lexicographic compare)
     if iAmInitiator and no ratchet state for peer:
       pqxdhInitiate(myIdentity, peerBundle)
       cache pending init payload in ratchet state
     else:
       wait — ratchet state will be created on first inbox arrival
       via pqxdhRespond
7. Start two async loops:
     poll inbox every 500ms
     read stdin lines
```

---

## Initiator / responder tiebreaker

Without a tiebreaker, both processes would see the other's bundle and both call `pqxdhInitiate` — producing two incompatible session states. The fix:

```
iAmInitiator = self.compareTo(peer) < 0   // alphabetical compare
```

| `self` | `peer` | Role |
|---|---|---|
| alice | bob | initiator (`a < b`) |
| bob | alice | responder |
| dan | eve | initiator |
| eve | dan | responder |

The responder must wait for an incoming `isInit=true` message before it can send anything. The stdin loop will refuse and print a warning if a responder tries to type before the handshake message arrives.

---

## Send path

```
sendMessage(state, plaintext):
  if KEM ratchet trigger (sendN > 0 && sendN % 10 == 0):
    encaps(remoteKemPk) → (kemCt, kem_ss)
    rootKey ← HKDF(rootKey, kem_ss)[:32]
    rotate own KEM keypair → new kemSk/kemPk
    advertise kemCt + new kemPk on the wire
  symmetric chain step:  HMAC(sendCK, 0x01) → msg_key
                         HMAC(sendCK, 0x02) → new sendCK
  AES-GCM seal(msg_key, random nonce, plaintext) → (ct, mac)
  emit WireMessage{ dhPk, kemPk?, kemCt?, nonce, ct, mac, msgN, isInit?, init payload? }
  encode envelope as JSON → notifyPeer(peerDb, self, envelope)
```

## Receive path

```
receiveMessage(state, msg):
  if msg.dhPk != remoteDhPk:                     # DH ratchet trigger
    rootKey, recvCK ← HKDF(rootKey, X25519(own dhSk × msg.dhPk))
    rotate own DH keypair → new dhSk/dhPk
    rootKey, sendCK ← HKDF(rootKey, X25519(own new dhSk × msg.dhPk))
    remoteDhPk ← msg.dhPk
    sendN = recvN = 0
  if msg.kemCt != null:                          # KEM ratchet receive
    kem_ss = decaps(own kemSk, msg.kemCt)
    rootKey ← HKDF(rootKey, kem_ss)[:32]
    rotate own KEM keypair → new kemSk/kemPk
    if msg.kemPk: remoteKemPk ← msg.kemPk
  if msg.kemPk != null && msg.kemCt == null:     # bare advertisement (init msg)
    remoteKemPk ← msg.kemPk
  symmetric chain step:  HMAC(recvCK, 0x01) → msg_key
                         HMAC(recvCK, 0x02) → new recvCK
  AES-GCM open(msg_key, msg.nonce, msg.ct, msg.mac) → plaintext
```

---

## Persistence cadence

Every send and every receive saves the keystore. SQLite writes are durable per default journal mode.

The two artifacts evolve independently:

- **SQLite** grows over time — `records` updates on bundle rotation, `inbox` grows by one row per incoming message.
- **Keystore JSON** is rewritten in full on each send/receive — keeps the on-disk form simple (no append journal).

---

## What's deliberately out of scope

- Encryption-at-rest of the keystore JSON.
- One-time pre-keys (OPKs).
- Multi-device per identity.
- Skipped-message-key cache for out-of-order delivery (all messages assumed in-order).
- Real network.
- Bundle rotation (SPK rotation would happen periodically in production — here the SPK lives for the keystore's entire lifetime).

---

## Sibling demos in `pq/demos/`

| Demo | Audience | Trades |
|---|---|---|
| `4_pq_chat/bin/demo.dart` | Algorithm reader | Single process, scripted, full BEFORE/STEP/AFTER trace. No I/O machinery. |
| `5_pq_demo/` (this) | Integration reader | Two processes, real transport, persistent state. Less inline trace; more "actual chat." |
