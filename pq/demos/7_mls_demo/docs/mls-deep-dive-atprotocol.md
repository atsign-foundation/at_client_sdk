# MLS Deep Dive — atProtocol Mapping

## 1. Topology

```
alice1 ──► @alice atServer ──► @bob atServer ──► bob2
              (relay)               (relay)
```

Servers are **blind relays**. They store ciphertexts and public key material but hold no private keys and cannot decrypt any payload. All E2E guarantees live in the clients.

Each atSign has an **MLS device group**:
- `@alice` group: `{ alice1, alice2, ... }`
- `@bob` group: `{ bob1, bob2, ... }`

Cross-atSign messages use **PQXDH + externalHpkePk** (see §3, §4).

---

## 2. What Each Server Stores

### @bob atServer

| Record | Written by | Visible to | Content |
|---|---|---|---|
| `@bob:actorBundle.demo7` | Bob's devices | Anyone | `{ ikPk, opkPool[], pqspkPool[] }` — public PQXDH prekeys |
| `@bob:mlsGroupInfo.demo7` | Bob's devices | Anyone | `{ externalHpkePk, epoch, treeHash, memberList }` |
| `@bob:keypackage.<deviceId>` | Enrolling device | Anyone | MLS KeyPackage — consumed on Add |
| `@bob:inbox.<hash>.demo7` | **Alice's devices** | Bob's devices (E2E) | PQXDH envelope + ciphertext |
| `@bob:mls.commit.<epoch>` | Bob's devices | Bob's devices (E2E) | TreeKEM Commit — intra-group epoch update |
| `@bob:mls.welcome.<deviceId>` | Bob's devices | Target device only (E2E) | PQXDH Welcome — epoch bootstrap |

**@alice atServer** mirrors the same structure for alice's group.

### What the server leaks (metadata)

- Who is communicating with whom (`fromIkPk` in inbox records)
- Timing and frequency of messages
- Which prekeys were consumed (`opkId`, `pqspkId`) → session count
- Group membership (`memberList` in GroupPublicInfo)
- When devices enroll/leave

This metadata is **unencrypted and unavoidable** in this design.

---

## 3. Key Rotation Granularity

| Granularity | What rotates | Mechanism | PQ? |
|---|---|---|---|
| **Per message** | `(key, nonce)` — one-time, deleted after use | Secret Tree sender ratchet: `ratchetSecret = HKDF(ratchetSecret, generation)` — symmetric, one-way | ✅ (inherited from epoch) |
| **Per N messages / threshold** | Full epoch: `encryptionSecret`, Secret Tree, `externalHpkePk`, `initSecret` | TreeKEM Update+Commit — X-Wing KEM encaps up direct path → new `commitSecret` → new epoch | ✅ X-Wing |
| **Per join/leave** | Same as above (forced Commit) | TreeKEM Commit with Add/Remove proposal | ✅ X-Wing |
| **Per conversation init** | `masterSecret` (cross-atSign) | PQXDH — consumes one OPK + one PQSPK from recipient's pool | ✅ X-Wing |

---

## 4. PQXDH — Two Places

### A. Cross-atSign Initial Message (alice1 → bob)

Alice encrypts to bob's atSign-level `ActorBundle`. Any bob device can decrypt; the server cannot.

**Alice encrypts:**
```
EK               = X25519.keygen()                    // ephemeral
DH1              = X25519(alice.ikSk,  bob.spkPk)
DH2              = X25519(EK.sk,       bob.ikPk)
DH3              = X25519(EK.sk,       bob.spkPk)
DH4              = X25519(EK.sk,       bob.opkPk)     // consumes one OPK
(ct_kem, ss_kem) = XWing.encaps(bob.pqspkPk)         // consumes one PQSPK (X-Wing, hybrid)
masterSecret     = HKDF(F || DH1||DH2||DH3||DH4||ss_kem, info="pqxdh-external")
ciphertext       = AES-GCM.seal(masterSecret, plaintext)

→ @bob:inbox.<hash>: { alice.ikPk, EK.pk, ct_kem, opkId, pqspkId, ciphertext, alice_mlDsaSig }
```

**Any bob device decrypts:**
```
DH1 = X25519(bob.spkSk,  alice.ikPk)
DH2 = X25519(bob.ikSk,   EK.pk)
DH3 = X25519(bob.spkSk,  EK.pk)
DH4 = X25519(bob.opkSk,  EK.pk)               // looked up by opkId
ss_kem = XWing.decaps(bob.pqspkSk, ct_kem)    // looked up by pqspkId
masterSecret = HKDF(F || DH1||DH2||DH3||DH4||ss_kem, info="pqxdh-external")
```

### B. New Device Joining the Group (Welcome)

Same PQXDH protocol but `masterSecret` seeds the MLS epoch chain instead of encrypting a single message (see §5 for full join flow).

### Ciphersuite invariant

**Every KEM operation uses X-Wing (ML-KEM-768 + X25519). No bare ML-KEM or bare X25519 anywhere.**

| Role | Algorithm |
|---|---|
| TreeKEM path nodes | X-Wing |
| PQXDH prekey encaps (`pqspkPk`) | X-Wing |
| Welcome encryption | X-Wing (via PQXDH) |
| AEAD | AES-256-GCM |
| Hash / KDF | SHA-256 / HKDF |
| Signatures | ML-DSA-65 |

Note: SPK (signed prekey) is **dropped**. Its only role was OPK exhaustion fallback. The correct response to an empty OPK/PQSPK pool is to refuse to send until the pool is replenished — silent degradation is worse than a failed send.

---

## 5. In-Group Message Encryption (Secret Tree)

```
encryptionSecret  (from epoch)
      │
      ▼
Secret Tree: leafSecret[i] = ExpandWithLabel(encryptionSecret, "leaf", i, 32)
      │
      ▼  per sender leaf
SenderRatchet: ratchetSecret_0 = leafSecret[myLeaf]

Per message N:
  key   = ExpandWithLabel(ratchetSecret_N, "key",    N, 32)
  nonce = ExpandWithLabel(ratchetSecret_N, "nonce",  N, 12)
  ratchetSecret_{N+1} = ExpandWithLabel(ratchetSecret_N, "secret", N, 32)
  // ratchetSecret_N deleted — key_N is now unreachable
  ciphertext = AES-GCM.seal(key, nonce, plaintext, aad=GroupContext)
```

Receiver derives the same `(key, nonce)` by running their copy of the sender's ratchet to generation N. Out-of-order messages cache skipped keys briefly then delete them.

---

## 6. TreeKEM — The Third Ratchet

In the Triple Ratchet (Demo 5), the third ratchet is an ML-KEM encap/decap step every N messages — asymmetric, post-quantum, provides PCS.

In MLS, **TreeKEM Update+Commit is the equivalent**:

```
alice1 triggers Update+Commit:
  newLeafSecret = XWing.rand(32)
  For each node up the direct path to root:
    pathSecret_n = DeriveSecret(pathSecret_{n-1}, "path")
    (nodePk_n, nodeSk_n) = XWing.keygen(DeriveSecret(pathSecret_n, "node"))
    For each copath sibling:
      seal(copath.hpkePk, pathSecret_n)   // O(log N) total seals
  commitSecret = DeriveSecret(pathSecret_root, "path")

New epoch:
  joinerSecret     = HKDF.extract(initSecret_prev, commitSecret)
  epochSecret      = DeriveSecret(joinerSecret, "epoch")
  encryptionSecret = DeriveSecret(epochSecret, "encryption")  → new Secret Tree
  externalHpkePk   = XWing.keygen(DeriveSecret(epochSecret, "external"))
  initSecret_next  = DeriveSecret(epochSecret, "init")
```

After a Commit: an attacker who had the previous epoch state cannot derive the new `encryptionSecret` without `newLeafSecret`. PCS is restored.

### Gap vs Triple Ratchet

| Property | Triple Ratchet | Demo 7 MLS |
|---|---|---|
| Per-message symmetric FS | ✅ | ✅ Secret Tree ratchet |
| Interactive DH per turn | ✅ automatic | ❌ no equivalent |
| Asymmetric PCS (KEM) | ✅ every N msgs | ✅ Update+Commit (explicit) |
| Post-quantum | ✅ ML-KEM | ✅ X-Wing |
| Deniability | ✅ | ❌ ML-DSA-65 sigs on Commits |

The **interactive DH ratchet** (second ratchet) has no MLS equivalent. In Signal, bob's reply automatically heals alice's state. In MLS, healing requires an explicit coordinated Commit. A periodic heartbeat Commit approximates this operationally but not structurally.

---

## 7. stale externalHpkePk (in-transit message)

Alice fetches epoch N's `externalHpkePk`. Bob's group commits to epoch N+1 before the message arrives. `externalHpkeSk_N` is gone from current state.

**Solution:** epoch cache on bob's devices.

```
wire message carries: { observedEpoch: N, enc, ct, tag }

on receive:
  sk = epochCache[N]?.externalHpkeSk
       ?? throw StaleEpochError
  plaintext = XWing.open(sk, enc, ct, tag)
```

Keep last K=3 epochs cached. After K commits, alice must re-fetch `GroupPublicInfo` and re-send. This is a bounded replay window — same tradeoff as TLS session ticket lifetime.

---

## 8. New Device Enrollment — atProtocol Mapping

### Current atPlatform (APKAM)

```
1. alice2 generates ephemeral RSA keypair
2. alice2 submits enrollment request → @alice atServer holds it
3. alice1 approves (signs with own private key)
4. alice2 receives selfEncryptionKey encrypted to its RSA public key
5. alice2 stores decrypted keys in .atKeys file
```

Key shared: **single symmetric `selfEncryptionKey`** — all devices share one secret. Server mediates the approval handshake.

### Demo 7 MLS

```
1. alice2 generates KeyPackage:
   { ikPk, opkPk, pqspkPk (X-Wing), leafPk (X-Wing), mlDsaPk }
   → @alice:keypackage.alice2.demo7  (public)

2. alice1 (online, existing member) fetches KeyPackage
   Issues Add + Commit:
   - TreeKEM: insert alice2 leaf, update direct path → commitSecret
   - derive new epochSecrets
   → @alice:mls.commit.<epoch>  (for all alice devices)

3. alice1 generates Welcome for alice2:
   PQXDH(alice1.ikSk, alice2.KeyPackage) → masterSecret
   encrypt { treeState, epoch, initSecret, confirmedTranscriptHash } → Welcome
   → @alice:mls.welcome.alice2.demo7

4. alice2 receives Welcome:
   PQXDH.receive(alice2.keys, alice1.ikPk) → masterSecret
   decrypt → bootstrap full epoch state (own leaf index, full tree, epochSecrets)
```

### Comparison

| | APKAM | MLS Join |
|---|---|---|
| Shared secret | Single `selfEncryptionKey` (all devices identical) | Each device has own leaf; `epochSecrets` derived per-epoch |
| Server role | Holds enrollment request; mediates approval | Blind relay; cannot participate in or block approval |
| Approver | Any enrolled device OR server-side OTP | **Must be an online group member** — server cannot proxy |
| Crypto cost | O(1): encrypt one key to new device's PK | O(log N): TreeKEM path update + Welcome generation |
| PCS | ❌ shared key never rotates per-device | ✅ Update+Commit evicts compromised device |
| Enrollment blocked if | Server is down | **All existing devices offline** — real operational gap |

### Critical gap

APKAM can complete enrollment server-side (OTP flow). MLS cannot — a Commit **must** come from an online group member. For an atSign with a single always-offline device, enrollment of a second device blocks indefinitely. This needs either:
- A designated "always-on" device (e.g., a server-side agent that is itself a group member — but that breaks the server-is-blind property), or
- A re-keying mechanism where alice2 bootstraps from a pre-generated Welcome that alice1 deposited in advance
