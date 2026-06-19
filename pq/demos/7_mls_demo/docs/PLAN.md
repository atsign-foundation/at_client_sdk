# Demo 7: Real MLS Group Chat (RFC 9420 + PQ)

## Context

Demo 6 implements an MLS-*shaped* group ratchet but with two critical gaps vs the real RFC:
1. **O(N) Commit**: flat per-member HPKE wraps instead of TreeKEM (O(log N))
2. **No per-message forward secrecy within an epoch**: `HKDF(groupSecret, "app|sender|idx")` is deterministic — anyone who learns `groupSecret` can recompute all past keys for that epoch

Demo 7 closes both gaps by implementing RFC 9420's core security algorithms in Dart on top of the existing OpenSSL 3.6 FFI layer. The result is group chat where:
- Each message derives a key via a *forward-advancing* sender ratchet (delete-after-use) — comparable to the Double/Triple Ratchet's per-message FS
- Commits only touch O(log N) nodes (TreeKEM direct path)
- Epoch chaining via `init_secret` carries FS across epoch boundaries
- All KEMs use X-Wing (ML-KEM-768 + X25519) → post-quantum

Same UX as Demo 6: multi-terminal group chat, SQLite transport, disk persistence.

---

## Security Comparison

| Property | Demo 6 | Demo 7 |
|---|---|---|
| Message FS within epoch | ❌ HKDF(static groupSecret, idx) — re-derivable | ✅ Secret Tree ratchet — advance & delete |
| PCS (heal after compromise) | Commit replaces groupSecret (O(N) seals) | TreeKEM Update+Commit (O(log N) seals) |
| Epoch-level FS | ✅ groupSecret discarded on Commit | ✅ init_secret chain |
| Commit complexity | O(N) | O(log N) |
| Transcript integrity | ❌ None | ✅ confirmedTranscriptHash chain |
| Join handshake | HPKE to leaf init key | ✅ PQXDH (X3DH + ML-KEM OPK) |
| Cross-actor initial msg | One-shot HPKE to externalHpkePk (no OPK, no FS) | ✅ PQXDH (X3DH + ML-KEM OPK, same as Signal initial msg) |
| Post-quantum KEM | ✅ X-Wing (ML-KEM-768 + X25519) | ✅ X-Wing (TreeKEM) + ML-KEM-768 (PQXDH) |
| Signature | ✅ ML-DSA-65 | ✅ ML-DSA-65 |

### Remaining gaps vs Triple Ratchet

| Property | Triple Ratchet (Demo 5) | Demo 7 | Gap |
|---|---|---|---|
| PCS healing granularity | Per-turn (every reply auto-heals) | Explicit Update+Commit | MLS needs a heartbeat to approach this |
| Interactive asymmetric FS | Fresh DH on every turn (both sides contribute) | Secret Tree is symmetric-only between Commits | Structural — MLS has no per-message DH step |
| PQ ratchet per-message | KEM ratchet every N messages | X-Wing KEM only at Commit time | Add periodic KEM heartbeat to close (non-standard) |
| Deniability | PQXDH + DR — no message proves alice sent it | ML-DSA-65 sigs on Commits break deniability | Structural MLS tradeoff |

---

## Where PQXDH Fits

PQXDH (Post-Quantum Extended Diffie-Hellman — Signal spec, 2023) applies in **two places**:

### A. Group Join Handshake (Welcome)

When a new member's Welcome is generated, instead of simple HPKE to their leaf init key:

```
// Joiner's KeyPackage publishes:
//   IK_pk    — identity key (X25519, long-term)  [signed by ML-DSA-65]
//   SPK_pk   — signed prekey (X25519, rotated weekly)
//   OPK_pk   — one-time prekey (X25519, single use)
//   PQSPK_pk — PQ signed prekey (X-Wing pk 1216 B, single use)  ← hybrid, not bare ML-KEM
//
// Sender (existing group member) computes:
EK = ephemeral X25519 keypair
DH1 = X25519(sender_IK_sk, joiner_SPK_pk)
DH2 = X25519(EK_sk,        joiner_IK_pk)
DH3 = X25519(EK_sk,        joiner_SPK_pk)
DH4 = X25519(EK_sk,        joiner_OPK_pk)    // empty bytes if no OPK
(ct_kem, ss_kem) = XWing.Encaps(joiner_PQSPK_pk)  // hybrid ML-KEM-768 + X25519
masterSecret = HKDF(F || DH1 || DH2 || DH3 || DH4 || ss_kem, info="pqxdh-join")
// F = 0xFF * 32 (Signal domain separator)
// → masterSecret replaces joiner_secret in the epoch derivation chain
```

Properties: deniability (X3DH) + quantum resistance (X-Wing OPK) + FS (EK ephemeral, OPK one-time).

**Why X-Wing for PQSPK**: even though DH1–DH4 already provide classical security, using X-Wing (not bare ML-KEM) means *every single KEM operation in Demo 7 is hybrid*. This is a defence-in-depth principle: no key material ever depends on a pure post-quantum primitive alone.

After join, all in-group messages use the **Secret Tree ratchet** (per-message FS). PQXDH is only for bootstrap.

### B. Cross-Actor Initial Message (External Sender)

Demo 6 uses one-shot HPKE to `externalHpkePk` for cross-group messages — no FS, no OPK consumption. Demo 7 replaces this with **actor-level PQXDH**, identical to Signal's initial message:

```
// Each actor publishes an ActorBundle (separate from MLS KeyPackage):
//   IK_pk, SPK_pk, [OPK_pk pool], PQSPK_pk pool
//   All signed by ML-DSA-65 identity key

// alice → bob (first message):
EK = ephemeral X25519
DH1 = X25519(alice.IK_sk, bob.SPK_pk)
DH2 = X25519(EK_sk,       bob.IK_pk)
DH3 = X25519(EK_sk,       bob.SPK_pk)
DH4 = X25519(EK_sk,       bob.OPK_pk)         // consume from bob's OPK pool
(ct_kem, ss_kem) = XWing.Encaps(bob.PQSPK_pk)  // hybrid ML-KEM-768 + X25519; consume PQSPK
masterSecret = HKDF(F || DH1 || DH2 || DH3 || DH4 || ss_kem, info="pqxdh-external")
externalMsg = AES-GCM.seal(masterSecret, plaintext)
wire: { alice.IK_pk, EK.pk, ct_kem, externalMsg, alice_sig_over_all }

// bob receives, runs PQXDH receiver → same masterSecret, decrypts
```

**Subsequent cross-actor messages** (same conversation): issue a new PQXDH with the next OPK/PQSPK from the pool.

---

## Architecture

```
pq/demos/7_mls_demo/
├── bin/
│   └── chat.dart               # Same terminal UX as Demo 6
├── lib/
│   ├── mls_crypto.dart         # RFC 9420 KDF primitives (ExpandWithLabel, DeriveSecret)
│   ├── key_package.dart        # MLS KeyPackage: IK + SPK + OPK + PQSPK + TreeKEM leaf PK
│   ├── actor_bundle.dart       # Actor-level PQXDH bundle: IK + SPK + OPK pool + PQSPK pool
│   ├── pqxdh.dart              # PQXDH sender + receiver (join handshake + cross-actor msg)
│   ├── ratchet_tree.dart       # TreeKEM: binary tree, direct-path commit, O(log N)
│   ├── secret_tree.dart        # MLS Secret Tree: per-sender forward-secret ratchets
│   ├── epoch.dart              # Epoch secret derivation chain (init→joiner→epoch→derived)
│   ├── mls_group.dart          # Group state machine (replaces Demo 6's group_ratchet.dart)
│   ├── wire.dart               # Wire types: MlsCiphertext, CommitPath, GroupContext, Welcome
│   ├── keystore.dart           # Identity + GroupState persistence (adapted from Demo 6)
│   ├── atserver.dart           # SQLite schema (unchanged from Demo 6)
│   └── transport.dart          # put/get/poll (unchanged from Demo 6)
└── pubspec.yaml                # depends on demo_6 (for openssl.dart) + ffi + sqlite3
```

**Crypto layer**: reuse `Crypto.load()` from `6_pq_mls_demo/lib/openssl.dart` — single factory with ML-KEM-768, ML-DSA-65, X-Wing, HPKE, AES-256-GCM, HKDF, RandBytes.

---

## Implementation Detail

### 1. `lib/mls_crypto.dart` — RFC 9420 KDF Primitives

```
ExpandWithLabel(secret, label, context, length):
  hkdfLabel = encode(length as u16) || "MLS 1.0 " || label || context
  return HKDF.expand(secret, hkdfLabel, length)

DeriveSecret(secret, label):
  return ExpandWithLabel(secret, label, "", 32)

// Used for both TreeKEM and Secret Tree
```

### 2. `lib/key_package.dart` + `lib/pqxdh.dart` — PQXDH Join Handshake

**KeyPackage** (each member pre-publishes to the transport store):
```dart
class KeyPackage {
  Uint8List ikPk;       // X25519 identity key (32 B)
  Uint8List spkPk;      // X25519 signed prekey (32 B)
  Uint8List spkSig;     // ML-DSA-65 signature over spkPk
  Uint8List? opkPk;     // X25519 one-time prekey (32 B, nullable — consumed on use)
  Uint8List pqspkPk;    // X-Wing one-time PQ prekey (1216 B) ← hybrid, not bare ML-KEM
  Uint8List pqspkSig;   // ML-DSA-65 sig over pqspkPk
  Uint8List leafPk;     // X-Wing PK for TreeKEM leaf (1216 B)
  Uint8List mlDsaPk;    // ML-DSA-65 identity pk (1952 B)
}
```

**PQXDH Sender** (existing member generating Welcome for joiner):
```
PqxdhSender.run(senderIkSk, joinerKeyPackage) → (masterSecret, envelope):
  EK = X25519.keygen()
  DH1 = X25519.dh(senderIkSk, joiner.spkPk)
  DH2 = X25519.dh(EK.sk, joiner.ikPk)
  DH3 = X25519.dh(EK.sk, joiner.spkPk)
  DH4 = X25519.dh(EK.sk, joiner.opkPk)  // empty bytes if no OPK
  (ct_kem, ss_kem) = XWing.Encaps(joiner.pqspkPk)   // hybrid ML-KEM-768 + X25519
  masterSecret = HKDF(F || DH1 || DH2 || DH3 || DH4 || ss_kem, info="pqxdh-mls-welcome")
  // F = 0xFF * 32 (Signal domain separator)
  envelope = { EK.pk, ct_kem }   // ct_kem is 1120 B (X-Wing ciphertext)
  return (masterSecret, envelope)
```

**PQXDH Receiver** (joiner decapsulating Welcome):
```
PqxdhReceiver.run(joinerKeyPackageSk, senderIkPk, envelope) → masterSecret:
  DH1 = X25519.dh(joiner.spkSk, senderIkPk)
  DH2 = X25519.dh(joiner.ikSk, envelope.EK_pk)
  DH3 = X25519.dh(joiner.spkSk, envelope.EK_pk)
  DH4 = X25519.dh(joiner.opkSk, envelope.EK_pk)  // empty if no OPK used
  ss_kem = XWing.Decaps(joiner.pqspkSk, envelope.ct_kem)   // hybrid ML-KEM-768 + X25519
  masterSecret = HKDF(F || DH1 || DH2 || DH3 || DH4 || ss_kem, info="pqxdh-mls-welcome")
```

`masterSecret` replaces the standard MLS `joiner_secret`. Plug into `epoch.dart`:
```
epochSecret chain: masterSecret → DeriveSecret("member") → DeriveSecret("epoch") → ...
```

Source to adapt: `pq/demos/5_pq_chat/` — has X25519+ML-KEM handshake logic.

---

### 3. `lib/ratchet_tree.dart` — TreeKEM

Left-balanced binary tree (standard RFC 9420 node numbering).

```dart
class TreeNode {
  Uint8List? hpkePk;   // X-Wing PK (1216 B); null = blank
  bool isBlank;
}
```

```
addLeaf(identity) → leafIndex
  Insert at next free leaf; blank ancestor nodes

commitPath(myLeafIndex, newLeafSecret, groupContext) → (CommitPath, commitSecret)
  // RFC 9420 § 7.5
  pathSecret_leaf = newLeafSecret
  For each node n going up direct path to root:
    pathSecret_n = DeriveSecret(pathSecret_{n-1}, "path")
    (nodePk_n, nodeSk_n) = DeriveKeypair(DeriveSecret(pathSecret_n, "node"))
      // DeriveKeypair: expand to 64B seed → X-Wing keygen
    update tree[n].hpkePk = nodePk_n
    For each copathNode c at this level:
      encryptedPathSecret = HPKE.seal(resolve(c)[0].hpkePk, groupContext, pathSecret_n)
  commitSecret = DeriveSecret(pathSecret_root, "path")
  return (CommitPath{encryptedPathSecrets[...]}, commitSecret)

applyCommitPath(senderLeafIdx, commitPath, myLeafIdx, groupContext) → commitSecret
  // Find copath node where my subtree is targeted
  // HPKE.open encrypted path secret
  // Re-derive upward to root
  // Update ancestor PKs from CommitPath
```

Resolve(node): non-blank leaf PKs in subtree — O(log N) total HPKE.seal calls across the whole path.

### 4. `lib/secret_tree.dart` — MLS Secret Tree

Per-epoch forward-secret message keys.

```
SecretTree seeded from epoch's encryptionSecret:
  initLeaf(leafIndex):
    leafSecret = ExpandWithLabel(encryptionSecret, "leaf", leafIndex as bytes, 32)

SenderRatchet (per leaf, per epoch):
  currentSecret, generation, skippedKeys: Map<int, (key, nonce)>

  deriveMessageKey(targetGeneration) → (key, nonce):
    while generation < targetGeneration:
      skippedKeys[generation] = (
        ExpandWithLabel(currentSecret, "key", generation, 32),
        ExpandWithLabel(currentSecret, "nonce", generation, 12)
      )
      currentSecret = ExpandWithLabel(currentSecret, "secret", generation, 32)
      generation++
    key = ExpandWithLabel(currentSecret, "key", generation, 32)
    nonce = ExpandWithLabel(currentSecret, "nonce", generation, 12)
    currentSecret = ExpandWithLabel(currentSecret, "secret", generation, 32)
    generation++
    return (key, nonce)
    // key is now unreachable from currentSecret (one-way)
```

### 5. `lib/epoch.dart` — Epoch Secret Chain

```
// RFC 9420 § 8.1
deriveEpochSecrets(initSecret, commitSecret, groupContext) → EpochSecrets:
  joinerSecret = ExpandWithLabel(
    HKDF.extract(initSecret, commitSecret), "joiner", groupContext, 32)
  memberSecret = DeriveSecret(joinerSecret, "member")
  epochSecret  = DeriveSecret(memberSecret, "epoch")

  return EpochSecrets(
    senderDataSecret     = DeriveSecret(epochSecret, "sender data"),
    encryptionSecret     = DeriveSecret(epochSecret, "encryption"),  // → seeds SecretTree
    exporterSecret       = DeriveSecret(epochSecret, "exporter"),
    authenticationSecret = DeriveSecret(epochSecret, "authentication"),
    initSecret           = DeriveSecret(epochSecret, "init"),        // → next epoch
    resumptionPsk        = DeriveSecret(epochSecret, "resumption"),
  )

deriveWelcomeKey(joinerSecret) → (key, nonce):
  welcomeSecret = DeriveSecret(joinerSecret, "welcome")
  key   = ExpandWithLabel(welcomeSecret, "key",   "", 32)
  nonce = ExpandWithLabel(welcomeSecret, "nonce", "", 12)
```

### 6. `lib/mls_group.dart` — Group State Machine

```dart
class MlsGroup {
  String groupId;
  int epoch;
  RatchetTree tree;
  EpochSecrets epochSecrets;
  SecretTree secretTree;
  Uint8List confirmedTranscriptHash;
  Uint8List initSecret;
  Map<int, EpochSecrets> epochCache;
}
```

- `createGroup(identity)` → epoch 0, single leaf, zeroed initSecret
- `addMember(identity)` → Add proposal → Commit → emit Welcome (PQXDH-encrypted)
- `commit(proposals)` → `tree.commitPath()` → derive new epoch → reset SecretTree
- `applyCommit(commit)` → `tree.applyCommitPath()` → advance epoch
- `applyWelcome(welcome)` → PQXDH.receive → derive epoch → bootstrap tree

**Message encrypt/decrypt:**
```
encrypt(plaintext, myLeafIdx):
  (key, nonce) = secretTree.getSenderRatchet(myLeafIdx).deriveMessageKey(generation)
  senderDataKey = ExpandWithLabel(epochSecrets.senderDataSecret, "key", senderDataNonce, 32)
  senderDataCt = AES-GCM.seal(senderDataKey, senderDataNonce,
                              encode(leafIndex, generation, contentType))
  ct = AES-GCM.seal(key, nonce, plaintext, aad=groupContext)
  return MlsCiphertext { senderDataNonce, senderDataCt, ct, groupId, epoch }

decrypt(MlsCiphertext):
  // Recover senderData → leafIndex, generation
  // Lookup sender ratchet → (key, nonce)
  // AES-GCM.open(ct)
```

**Transcript hash** (every Commit):
```
confirmedTranscriptHash = SHA256(confirmedTranscriptHash_prev || CommitContent)
```

### 7. `lib/wire.dart` — New Wire Types

```dart
class CommitPath {
  List<CommitPathNode> nodes;
}
class CommitPathNode {
  Uint8List nodePk;
  List<HpkeCiphertext> encryptedPathSecrets;
}
class MlsCiphertext {
  String groupId; int epoch;
  Uint8List senderDataNonce, senderDataCt;
  Uint8List ct;
}
class GroupContext {
  String groupId; int epoch;
  Uint8List treeHash;
  Uint8List confirmedTranscriptHash;
}
```

---

## Ciphersuite

**Invariant: every KEM operation uses X-Wing (ML-KEM-768 + X25519). No bare ML-KEM or bare X25519 is used for key encapsulation anywhere.**

| Role | Algorithm | Sizes |
|---|---|---|
| KEM (TreeKEM nodes, Welcome) | X-Wing (ML-KEM-768 + X25519) | PK 1216 B, CT 1120 B |
| KEM (PQXDH prekey — join + cross-actor) | X-Wing (ML-KEM-768 + X25519) | PK 1216 B, CT 1120 B |
| AEAD | AES-256-GCM | Key 32 B, Nonce 12 B, Tag 16 B |
| Hash / KDF | SHA-256 / HKDF-SHA256 | — |
| Signature | ML-DSA-65 | PK 1952 B, Sig 3309 B |

---

## File Dependencies

| Source | Usage |
|---|---|
| `demo_6/lib/openssl.dart` | Reused as-is (`Crypto.load()`) |
| `demo_6/lib/atserver.dart` | Copy unchanged |
| `demo_6/lib/transport.dart` | Copy unchanged |
| `demo_6/lib/keystore.dart` | Adapt for new epoch/tree state |
| `demo_5/` | Reference for PQXDH X25519+ML-KEM logic |

`pubspec.yaml`:
```yaml
dependencies:
  ffi: ^2.1.0
  sqlite3: ^2.4.0
  demo_6:
    path: ../6_pq_mls_demo
```

---

## Tests (TDD — write first)

| Test file | What it covers |
|---|---|
| `test/mls_crypto_test.dart` | ExpandWithLabel, DeriveSecret vs RFC 9420 test vectors |
| `test/pqxdh_test.dart` | Join PQXDH round-trip; masterSecret matches both sides; ML-KEM ct unrecoverable without pqspkSk |
| `test/pqxdh_external_test.dart` | Cross-actor PQXDH round-trip; OPK consumed; past masterSecret unrecoverable |
| `test/ratchet_tree_test.dart` | commitPath + applyCommitPath for N=2,4,8; commitSecret matches |
| `test/secret_tree_test.dart` | In-order + out-of-order key derivation; keys not re-derivable after advance |
| `test/epoch_test.dart` | Two epochs produce different encryptionSecrets; initSecret chain is one-way |
| `test/mls_group_test.dart` | 3-party: PQXDH join, commit, send/recv, remove, commit, cross-epoch FS |

Run: `dart test` inside `7_mls_demo/`

End-to-end: three terminals:
```
dart run bin/chat.dart alice
dart run bin/chat.dart bob
dart run bin/chat.dart carol
```
1. Alice creates group, Bob joins → PQXDH Welcome flow
2. Carol joins → TreeKEM Commit with 3 leaves
3. Messages decrypt across all members
4. Carol removed → her terminal can't decrypt new messages
