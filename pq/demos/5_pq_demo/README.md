# 5_pq_demo — End-to-end PQ chat (SQLite transport + JSON keystore)

Platform-agnostic post-quantum chat demo. Two parties, two terminals. Each
holds a JSON keystore on disk + a local SQLite store standing in for the
network.

```sh
# Terminal 1
dart run bin/chat.dart alice bob

# Terminal 2
dart run bin/chat.dart bob alice
```

Lexicographically smaller name becomes the **initiator** (here: `alice`).
She runs the PQXDH handshake against bob's published bundle; bob waits and
reconstructs the session on receipt of alice's first message.

## On-disk state per party

| File | Role |
|---|---|
| `<name>_keystore.json` | Long-lived identity + signed pre-key + per-peer ratchet state. Plaintext JSON. |
| `<name>_store.db` | SQLite. `records` table = published key-value pairs (the pre-key bundle). `inbox` table = FIFO of incoming encrypted messages from peers. |

## Inspecting the running demo

```sh
# What did alice publish?
sqlite3 alice_store.db 'SELECT key, length(value) FROM records;'

# What's in alice's inbox?
sqlite3 alice_store.db \
  'SELECT id, from_name, length(value), consumed FROM inbox ORDER BY id;'

# Peek at alice's persisted ratchet state for bob
jq '.ratchets.bob' alice_keystore.json
```

## What you'll see in the trace

```
[keystore loaded for "alice" ...]
[opened alice_store.db]
[put "prekeyBundle" → records (2768B)]
[waiting for "bob"'s prekeyBundle…]
[peeked "bob"/prekeyBundle]
[verified bob's SPK signature  ✓]
[ratchet] PQXDH initiated (role: INITIATOR); first send carries init payload
...
[ratchet] sent init msg (carries PQXDH init payload, 2407B)
[you] hi bob
[ratchet] DH ratchet step on receive
[bob → alice] hi alice
```

Ratchet events printed in cyan; transport events in dim grey.

## What this demo demonstrates

1. **Key generation on first run** — identity (X25519 + Ed25519), signed pre-key (X25519 + ML-KEM-768), Ed25519 signature.
2. **Bundle publication via a local kv store** — `put('prekeyBundle', <json>)` writes to the party's own SQLite.
3. **Bundle lookup against peer's store** — `peekPeer(peerDb, 'prekeyBundle')`.
4. **SPK signature verification** before any handshake.
5. **PQXDH handshake** — 3 X25519 DHs + 1 ML-KEM Encaps → shared `rootKey`.
6. **Triple ratchet runtime** — symmetric chain per message, DH ratchet on direction flip, KEM ratchet every 10 sends.
7. **Persistence** — keystore + sqlite both survive process restart; chat resumes from previous state.

## What's deliberately out of scope

- Encryption-at-rest of the keystore JSON (production would wrap it).
- One-time pre-keys (OPKs).
- Multi-device per identity.
- Skipped-message-key cache for out-of-order delivery.
- Real network — the SQLite-backed inbox stands in.

See `docs/ARCHITECTURE.md` for full component walkthrough.

## Sibling demos

| Demo | What it shows |
|---|---|
| `4_pq_chat/` | Single-process scripted narrative of the Triple Ratchet — full BEFORE/STEP/AFTER trace, no I/O machinery. |
| `5_pq_demo/` | This demo — two-terminal interactive chat with a real transport. |

## Dependencies

- `cryptography: ^2.7.0` — X25519, Ed25519, HKDF-SHA256, HMAC-SHA256, AES-256-GCM
- `pqcrypto: ^0.1.0` — ML-KEM-768
- `sqlite3: ^2.4.0` — local DB transport
