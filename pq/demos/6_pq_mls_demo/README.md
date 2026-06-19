# 6_pq_mls_demo — N-actor PQ chat with group ratchet over OpenSSL FFI

End-to-end post-quantum chat between two parties — **alice** and **bob** —
where each can run **N actors** (devices). One MLS-shaped group ratchet per
name keeps every actor on that name in sync; cross-name messaging uses an
external-sender HPKE construction.

```sh
# Pre-flight
dart pub get
dart run bin/smoke.dart        # confirm OpenSSL FFI works
dart run bin/ratchet_test.dart # confirm the ratchet algorithm works
```

Then open four terminals:

```sh
# Terminal 1 — alice's first device, bootstraps alice's group
dart run bin/chat.dart alice:device1 bob

# Terminal 2 — bob's first device, bootstraps bob's group
dart run bin/chat.dart bob:phone alice

# Terminal 3 — alice's second device, joins alice's group via Welcome
dart run bin/chat.dart alice:device2 bob

# Terminal 4 — bob's second device, joins bob's group via Welcome
dart run bin/chat.dart bob:laptop alice
```

Type anything in any terminal — every other actor (on either side) sees it.

## Slash commands inside the chat

| Command | Effect |
|---|---|
| `/quit` | Exit |
| `/remove <device_id>` | Commit-remove a device from your group (PCS rotation) |
| `/heartbeat` | Manual PCS rotation — empty Commit, rotates `group_secret` + `externalHpkeSk` |
| `<any other text>` | Send as an in-group msg AND as an external msg to the peer's group |

## On-disk artifacts

| File | What |
|---|---|
| `<name>-<device>_keystore.json` | Per-actor: identity (ML-DSA + ML-KEM) + ownGroup state + peer caches |
| `<name>_store.db` | Per-name SQLite (shared by all actors of that name): `records` + `inbox` tables |

Inspect:

```sh
sqlite3 alice_store.db 'SELECT key, length(value) FROM records;'
sqlite3 alice_store.db 'SELECT id, target_device, from_device, msg_type, length(value), consumed_by FROM inbox ORDER BY id;'
jq '.ownGroup | {epoch, members: [.members[].deviceId]}' alice-device1_keystore.json
```

## Reset (start fresh)

```sh
dart run bin/chat.dart alice:device1 bob --reset
```

Or wipe everything:

```sh
rm -f *_store.db *_store.db-* *_keystore.json
```

## Crypto stack

All primitives via OpenSSL 3.6 via Dart FFI through `libcrypto.dylib`.

| Layer | Algorithm |
|---|---|
| KEM | **X-Wing** (X25519 + ML-KEM-768 hybrid, draft-connolly-cfrg-xwing-kem) |
| Signature | ML-DSA-65 (FIPS 204) |
| AEAD | AES-256-GCM |
| KDF | HKDF-SHA256 |
| Combiner | SHA3-256 (X-Wing) |
| MAC | HMAC-SHA256 |
| Hybrid encryption | HPKE base mode (Dart-built atop the above) |

The KEM is **hybrid PQ + classical**: even if ML-KEM-768 is broken, the X25519
leg keeps the shared secret confidential, and vice versa. X-Wing sizes:
pk=1216 B, sk=2464 B, ct=1120 B, ss=32 B.

No `cryptography` package. No `pqcrypto` Dart package. ML-KEM wrapper class
imported via `path` dep from [demo 3](../3_openssl_ffi_and_pqcrypto_package_comparison/lib/ml_kem.dart).

## What the demo demonstrates

1. **PQ key generation** — ML-DSA identity, ML-KEM HPKE keypair per device, all via OpenSSL EVP.
2. **One group per name** — alice's group spans her devices; bob's group spans his.
3. **Group ratchet** — `group_secret` + `externalHpkeSk` rotate on every Commit (Add/Remove/Update).
4. **Per-member HPKE wraps** — instead of TreeKEM, each Commit ships one HPKE-sealed payload per current member.
5. **External-sender mode** — alice does **one** HPKE encrypt to bob's group external public key; all of bob's devices decrypt with their shared `externalHpkeSk`. Sender never enumerates recipient devices.
6. **TOFU signer pinning** — first ML-DSA PK seen for a peer device is pinned; subsequent mismatches rejected.
7. **Forward secrecy** — old `group_secret` discarded on every Commit; last 2 epochs' secrets retained in a bounded cache for out-of-order delivery.
8. **Post-compromise security** — every Commit injects fresh randomness; the leader auto-fires a heartbeat Commit every 10 in-epoch messages (`/heartbeat` for manual). `/remove <device>` also rotates.
9. **Hybrid PQ + classical** — X-Wing combines X25519 with ML-KEM-768; an attacker must break both to recover the shared secret.

See `docs/ARCHITECTURE.md` for the full walkthrough.

## What it deliberately skips

- TreeKEM (O(log N) — we use O(N) flat wraps for simplicity)
- PSK, external Commits, group resumption (full MLS features not needed for the demo)
- Multi-device key sync via OOB pairing
- Real network — the SQLite `inbox` stands in

## Sibling demos

| | |
|---|---|
| `3_openssl_ffi_*` | ML-KEM-768 cross-impl comparison; owns the OpenSslMlKem768 FFI class |
| `4_pqxdh_spqr_demo` | Single-process scripted Triple Ratchet narrative (the algorithm) |
| `5_pq_chat` | Two-party Triple Ratchet interactive chat |
| **6_pq_mls_demo** | **This demo — N-on-N device chat with group ratchet** |
