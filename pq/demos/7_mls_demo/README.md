# 7_mls_demo — RFC 9420 MLS group chat with TreeKEM, Secret Tree, and PQXDH

Post-quantum group chat that closes the two security gaps left open in Demo 6:

1. **Per-message forward secrecy within an epoch** — Demo 6 derived all message keys from a static `groupSecret`; anyone who learns it can recover every message in that epoch. Demo 7 uses the MLS **Secret Tree** ratchet: each message key is derived from an advancing per-sender counter and immediately forgotten. Past keys are unreachable from current state.
2. **O(log N) Commit** — Demo 6 sealed one HPKE ciphertext per member on every Commit. Demo 7 uses **TreeKEM**: a left-balanced binary Ratchet Tree where a Commit only touches the O(log N) nodes on the committer's direct path. An 8-member group needs 3 path-secret ciphertexts, not 8.

Same SQLite-backed multi-terminal UX as Demo 6; upgraded crypto underneath.

## Quick start

```sh
cd pq/demos/7_mls_demo
dart pub get
```

Open three terminals:

```sh
# Terminal 1 — alice, first device (creates alice_group)
dart run bin/chat.dart alice

# Terminal 2 — bob, first device (creates bob_group)
dart run bin/chat.dart bob

# Terminal 3 — alice, second device (joins alice_group via PQXDH Welcome)
dart run bin/chat.dart alice phone
```

Type anything — all other terminals see it. Ctrl+C to quit.

Alice's two devices share one group and one SQLite DB. Cross-actor messages from alice reach bob's group via X-Wing HPKE to bob's epoch-derived `externalHpkePk`. Any bob device can decrypt.

## Flags

| Flag | Effect |
|---|---|
| `--reset` | Delete keystores and DB for this actor, start fresh |
| `--verbose` | Print per-message key-derivation diagnostics |
| `--tree` | Print Ratchet Tree state after every Commit |

## On-disk artifacts

| File | What |
|---|---|
| `<name>.db` | Per-name SQLite — `records` (KV store) + `inbox` tables |
| `<name>_<device>_mls7_ks.json` | Per-device keystore — identity keys (ML-DSA, X-Wing), MLS group state, epoch cache |

Inspect:

```sh
sqlite3 alice.db 'SELECT key, length(value) FROM records;'
sqlite3 alice.db 'SELECT id, from_device, msg_type, consumed_by FROM inbox ORDER BY id;'
jq '{epoch, members: [.groupState.leafIndexMember[]]}' alice_alice:main_mls7_ks.json
```

Reset a single actor:

```sh
dart run bin/chat.dart alice --reset
```

Wipe everything:

```sh
rm -f *.db *.db-shm *.db-wal *_mls7_ks.json
```

## Crypto stack

All primitives via OpenSSL 3.6, Dart FFI, `libcrypto.dylib` — no `cryptography` or `pqcrypto` packages.

| Layer | Algorithm | Notes |
|---|---|---|
| KEM | **X-Wing** (ML-KEM-768 + X25519 hybrid) | PK 1216 B, CT 1120 B, SS 32 B |
| AEAD | AES-256-GCM | Key 32 B, Nonce 12 B |
| Hash / KDF | SHA-256 / HKDF-SHA256 | RFC 9420 `ExpandWithLabel` + `DeriveSecret` |
| Signature | ML-DSA-65 (FIPS 204) | Group ops only |
| MAC | HMAC-SHA256 | App message auth (deniable) |

**Ciphersuite invariant:** every KEM operation uses X-Wing. No bare ML-KEM and no bare X25519 for key encapsulation anywhere.

## What it demonstrates

1. **RFC 9420 Secret Tree** — per-sender ratchet seeded from the epoch's `encryptionSecret`; each `(key, nonce)` pair is derived and deleted, so compromise of current state cannot recover past messages within the epoch.
2. **TreeKEM direct-path Commit** — X-Wing encaps/decaps up the O(log N) direct path; `commitSecret` feeds the next epoch without touching non-path nodes.
3. **Epoch chain** — `initSecret` threads epochs together; learning an epoch's secrets does not recover any earlier epoch (`init_secret` is one-way).
4. **PQXDH Welcome (group join)** — new device bootstrap via X3DH (DH₁–DH₄) + X-Wing one-time PQ prekey; `masterSecret` replaces the standard MLS `joiner_secret`; the admitting member need not stay online after sending the Welcome.
5. **Automatic PCS** — every 3 messages the sender fires an Update+Commit, rotating its leaf X-Wing keypair and deriving a new epoch. No manual trigger needed.
6. **External-sender HPKE (cross-actor)** — cross-actor messages are encrypted to the recipient group's `externalHpkePk` (epoch-derived, X-Wing); any member device can decrypt; sender never enumerates recipient devices.
7. **Epoch cache** — last 3 epoch secrets retained in memory so out-of-order messages from a stale epoch still decrypt.
8. **Multi-device** — N devices per name share one SQLite DB; second+ devices join via PQXDH Welcome and stay in sync through Commits.

## Security comparison vs Demo 6

| Property | Demo 6 | Demo 7 |
|---|---|---|
| Per-message FS within epoch | ❌ `HKDF(static groupSecret, idx)` — all past keys re-derivable | ✅ Secret Tree ratchet — advance and delete |
| Commit complexity | O(N) HPKE seals per member | ✅ O(log N) TreeKEM |
| Epoch-level FS | ✅ `groupSecret` discarded on Commit | ✅ `initSecret` one-way chain |
| Join handshake | HPKE to leaf init key (no OPK, no FS) | ✅ PQXDH (X3DH + X-Wing OPK) |
| Transcript integrity | ❌ None | ✅ `confirmedTranscriptHash` chain |
| PCS rotation | Manual `/heartbeat` or every 10 msgs | ✅ Automatic every 3 messages |

## What it deliberately skips

- **PSK, external Commits, group resumption** — full MLS features outside the demo scope.
- **Cross-actor PQXDH initial message** — subsequent messages use `externalHpkePk` (one-shot HPKE), not a fresh PQXDH per conversation; OPK pool management is not implemented.
- **Cross-actor per-message FS** — the symmetric ratchet from the PQXDH master secret is device-bound, not distributed across multi-device groups.
- **Real network** — SQLite inbox is the transport.
- **Authorization on join** — any device can send a `JoinRequest`; production would require APKAM OTP or ML-DSA cross-signature.

## Tests

```sh
dart test
```

| File | Covers |
|---|---|
| `test/mls_crypto_test.dart` | `ExpandWithLabel`, `DeriveSecret` vs RFC 9420 test vectors |
| `test/pqxdh_test.dart` | Join PQXDH round-trip; `masterSecret` matches both sides |
| `test/ratchet_tree_test.dart` | `commitPath` + `applyCommitPath` for N=2, 4, 8; `commitSecret` matches |
| `test/secret_tree_test.dart` | In-order and out-of-order key derivation; keys not re-derivable after advance |
| `test/epoch_test.dart` | Two epochs produce different `encryptionSecret`s; `initSecret` chain is one-way |
| `test/mls_group_test.dart` | 3-party: PQXDH join, commit, send/recv, remove, cross-epoch FS |

## Sibling demos

| Demo | What it is |
|---|---|
| `3_openssl_ffi_*` | ML-KEM-768 FFI cross-impl comparison; owns the OpenSSL FFI layer |
| `4_pqxdh_spqr_demo` | Single-process Triple Ratchet narrative (the algorithm) |
| `5_pq_chat` | Two-party Triple Ratchet interactive chat |
| `6_pq_mls_demo` | N-device group chat with MLS-shaped ratchet (O(N) Commit, no Secret Tree) |
| **7_mls_demo** | **This demo — full RFC 9420 core: TreeKEM + Secret Tree + PQXDH** |
