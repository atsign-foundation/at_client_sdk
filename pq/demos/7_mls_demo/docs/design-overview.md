# Demo 7 — PQ Group Messaging Design

> A post-quantum group messaging protocol for atPlatform, targeting ~90% of Triple Ratchet security with full multi-device support.

---

## The Problem

atPlatform has multiple devices per atSign. A message from `@alice` to `@bob` travels:

```
alice1 ──► @alice atServer ──► @bob atServer ──► bob2
                (relay)              (relay)
```

We need:
- E2E encryption (servers see only ciphertext)
- Multi-device (any alice device can send, any bob device can decrypt)
- Post-quantum resistance
- Forward secrecy + post-compromise security (PCS)
- N devices per atSign, not just 2

Signal's Double/Triple Ratchet solves the 2-party case beautifully. It breaks for N devices because ratchet state belongs to a device, not an identity.

**This design layers MLS (RFC 9420) for device-group management on top of a Triple-Ratchet-inspired cross-actor protocol.**

---

## Two Distinct Problems

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│         @alice's group          │     │          @bob's group           │
│   alice1 ◄──MLS──► alice2       │     │   bob1 ◄──MLS──► bob2           │
│         (intra-group)           │     │         (intra-group)           │
└──────────────┬──────────────────┘     └──────────────┬──────────────────┘
               │        cross-actor messaging           │
               └──────────────────────────────────────►│
```

1. **Intra-group:** alice1 ↔ alice2 — multiple devices under the same atSign. Solved by MLS.
2. **Cross-actor:** @alice ↔ @bob — two separate atSigns. Solved by a Triple-Ratchet-inspired bilateral protocol.

---

## Ciphersuite Invariant

> **Every KEM operation uses X-Wing (ML-KEM-768 + X25519). No bare ML-KEM or bare X25519 anywhere.**

| Role | Algorithm |
|---|---|
| All KEMs | X-Wing (ML-KEM-768 + X25519 hybrid) |
| Dedicated PQ KEM (third ratchet) | ML-KEM-768 standalone |
| AEAD | AES-256-GCM |
| Hash / KDF | SHA-256 / HKDF-SHA256 |
| Signatures (group ops only) | ML-DSA-65 |
| App message auth | HMAC(membershipKey) — deniable |

---

## Part 1: Intra-Group (MLS)

### Group Structure

Each atSign's devices form an MLS group. The group state is a **left-balanced binary Ratchet Tree** where each leaf is a device.

```
            7 (root)
          /         \
        3               11
       / \             /  \
      1    5         9      13
     / \  / \       / \    / \
    L0 L1 L2 L3   L4 L5  L6  L7

    alice1 alice2 alice3 ...
```

Every member holds:
- Their own leaf private key (X-Wing)
- All ancestor node public keys
- Current epoch secrets

### Epoch Secrets (The Root of Everything)

All security material for an epoch flows from a single derivation:

```
initSecret (prev epoch)
    +
commitSecret (from TreeKEM)
         │
         ▼
    epochSecret
         │
    ├── encryptionSecret  ──► seeds Secret Tree (ratchet 1)
    ├── externalHpkeSk    ──► X-Wing keypair   (ratchet 2)
    ├── externalKemSk     ──► ML-KEM keypair   (ratchet 3)
    ├── membershipKey     ──► HMAC for app msg auth
    ├── senderDataSecret  ──► encrypts sender metadata
    └── initSecret        ──► feeds next epoch
```

Every member independently derives all of these. No distribution needed.

### Ratchet 1 — Secret Tree (Per Message)

```
encryptionSecret
    │
    ├── leafSecret[alice1] = ExpandWithLabel(encryptionSecret, "leaf", 0, 32)
    ├── leafSecret[alice2] = ExpandWithLabel(encryptionSecret, "leaf", 1, 32)
    └── ...

Per message N from alice1:
    key_N   = ExpandWithLabel(ratchetSecret_N, "key",    N, 32)
    nonce_N = ExpandWithLabel(ratchetSecret_N, "nonce",  N, 12)
    ratchetSecret_{N+1} = ExpandWithLabel(ratchetSecret_N, "secret", N, 32)
    // ratchetSecret_N deleted — key_N is now unreachable
```

alice2 independently derives `leafSecret[alice1]`, advances to generation N, gets the same `(key_N, nonce_N)`. **No communication needed — pure derivation.**

Forward secrecy: advance and delete. Compromise of current state cannot recover past keys.

### Ratchet 2 — TreeKEM Commit (Asymmetric, Commit-Gated)

When a member commits (e.g. alice1 sends a message and attaches an Update):

```
alice1 generates newLeafSecret
Direct path: alice1's leaf → parent → grandparent → root

For each level up the path:
    pathSecret_n = DeriveSecret(pathSecret_{n-1}, "path")
    new node keypair = XWing.keygen(DeriveSecret(pathSecret_n, "node"))

For each copath sibling at that level:
    XWing.seal(copathNode.hpkePk, pathSecret_n)
```

**What gets broadcast (one message to all N members):**

```
MlsCommit {
  commitPath: [
    { newNodePk, encryptedPathSecret → sealed to copath[0] },  // level 1
    { newNodePk, encryptedPathSecret → sealed to copath[1] },  // level 2
    { newNodePk, encryptedPathSecret → sealed to copath[2] },  // root
  ]
  signerDevice, signature  // ML-DSA-65 — accountability for group ops
}
```

8 members → 3 ciphertexts. **O(log N), not O(N).**

Each member decrypts exactly one ciphertext (the one targeting their copath position), re-derives up to root → gets `commitSecret` → derives new `epochSecret` → new Secret Tree, new external keys.

**What a passive attacker who intercepts the broadcast gets:**

```
✓  New node public keys       — public, harmless
✓  3 X-Wing ciphertexts       — useless without current node private key
✗  pathSecrets                — encrypted
✗  commitSecret               — unreachable
✗  new epochSecret            — unreachable
✗  any message keys           — unreachable
```

The broadcast is safe to intercept entirely.

### Automatic DH Ratchet (The Key Innovation)

Signal's DH ratchet heals automatically when the other party replies. We approximate this:

```
alice1 sends a message:
  1. Encrypt via Secret Tree (ratchet 1)
  2. Attach UpdateProposal(newLeafPk) to the wire message

bob's group receives, any bob device replies:
  1. Apply alice's UpdateProposal → Commit → new epoch
  2. Encrypt reply via new Secret Tree
```

Healing happens on the **next reply**, not manually triggered. alice's leaf key rotates automatically as a side effect of conversation. This is commit-gated (not per-message like Signal) but requires zero explicit coordination.

### New Device Joins (PQXDH Welcome)

Each device pre-publishes a KeyPackage:

```
KeyPackage {
  ikPk:     X25519 identity key        (32 B)
  opkPk:    X25519 one-time prekey     (32 B, consumed on use)
  pqspkPk:  X-Wing one-time PQ prekey  (1216 B, consumed on use)
  leafPk:   X-Wing TreeKEM leaf key    (1216 B)
  mlDsaPk:  ML-DSA-65 identity key     (1952 B)
}
```

Existing member generates Welcome via **PQXDH** (not bare HPKE):

```
EK               = X25519.keygen()                    // ephemeral
DH1              = X25519(sender.ikSk,  joiner.opkPk)
DH2              = X25519(EK.sk,        joiner.ikPk)
DH3              = X25519(EK.sk,        joiner.opkPk)
(ct_kem, ss_kem) = XWing.encaps(joiner.pqspkPk)      // hybrid PQ
masterSecret     = HKDF(F || DH1||DH2||DH3||ss_kem,
                        info="pqxdh-join")
// F = 0xFF×32 (Signal domain separator)

Welcome = AES-GCM.seal(masterSecret,
           { treeState, epoch, initSecret, confirmedTranscriptHash })
```

Joiner runs PQXDH receiver side → same `masterSecret` → decrypts Welcome → bootstraps full group state. **No existing member needs to stay online after sending Welcome.**

**Authorization gap:** anyone can send a JoinRequest. The admitting member must verify the joining device belongs to the atSign — via ML-DSA cross-signature or an enrollment token (mirrors APKAM OTP).

---

## Part 2: Cross-Actor Messaging

### Three Ratchets for Cross-Actor

Two epoch-derived sibling keys sit alongside `externalHpkeSk`:

```
epochSecret
    ├── externalHpkeSk  → X-Wing keypair    (ratchet 2: bilateral DH-like)
    └── externalKemSk   → ML-KEM-768 keypair (ratchet 3: dedicated PQ)
```

Both published as `externalHpkePk` and `externalKemPk` in `GroupPublicInfo` on the atServer. Both rotate on every Commit. Any alice device can decrypt (derived from shared epochSecret — multi-device safe).

### Message Encryption (alice → bob)

```
alice fetches bob's GroupPublicInfo:
    { externalHpkePk, externalKemPk, epoch }

// Ratchet 2: bilateral X-Wing contribution
(enc_hpke, ss_hpke) = XWing.encaps(bob.externalHpkePk)

// Ratchet 3: dedicated ML-KEM contribution
(enc_kem, ss_kem)   = MLKem.encaps(bob.externalKemPk)

// Both sides contribute (bilateral)
messageKey = HKDF(
    ss_hpke || alice.externalHpkePk ||    // alice's epoch key mixed in
    ss_kem  || alice.externalKemPk,        // alice's PQ epoch key mixed in
    info="cross-actor"
)

ct = AES-GCM.seal(messageKey, plaintext)
mac = HMAC(alice.membershipKey, ct)        // deniable auth — not a signature

wire → @bob:inbox.<hash>: {
    enc_hpke, enc_kem, ct, mac,
    alice.externalHpkePk, alice.externalKemPk, alice.epoch,
    observedEpoch: bob.epoch
}
```

### Message Decryption (any bob device)

```
ss_hpke = XWing.decaps(bob.externalHpkeSk, enc_hpke)
ss_kem  = MLKem.decaps(bob.externalKemSk,  enc_kem)
messageKey = HKDF(ss_hpke || alice.externalHpkePk ||
                  ss_kem  || alice.externalKemPk,
                  info="cross-actor")
plaintext = AES-GCM.open(messageKey, ct)
// verify HMAC(alice.membershipKey, ct)  ← needs alice's membershipKey
```

**Note on membershipKey verification:** bob doesn't have alice's `membershipKey`. For cross-actor auth, fall back to alice publishing her `membershipKey` for the current epoch (or use a separate MAC key derived from the PQXDH initial handshake).

### Stale Epoch Handling

Alice fetches bob's `externalHpkePk` at epoch N. Bob commits to epoch N+1 before message arrives.

```
wire message carries: { observedEpoch: N, enc_hpke, enc_kem, ct }

bob device on receive:
    hpkeSk = epochCache[N]?.externalHpkeSk ?? throw StaleEpochError
    kemSk  = epochCache[N]?.externalKemSk  ?? throw StaleEpochError
```

Keep last K=3 epochs cached. After K commits: alice must re-fetch `GroupPublicInfo` and re-send.

### Cross-Actor Symmetric Ratchet (First Ratchet for Cross-Actor)

After the PQXDH initial handshake, derive a shared chain key both sides advance independently:

```
// After PQXDH: both sides have masterSecret
chainKey_0 = HKDF(masterSecret, "cross-chain")

// Per message N:
msgKey_N       = HKDF(chainKey_N, "msg")
chainKey_{N+1} = HKDF(chainKey_N, "advance")
// delete chainKey_N — msgKey_N now unreachable
```

Since `chainKey` is derived from `masterSecret` (PQXDH output), and PQXDH uses the actor's `opkPk`/`pqspkPk` — any device that participated in the PQXDH can advance the chain. **Multi-device gap:** chain state belongs to the device that did PQXDH. Other devices need it distributed via the MLS group.

---

## What Lives on Each Server

### @bob atServer

| Record | Written by | Readable by | Content |
|---|---|---|---|
| `@bob:actorBundle` | Bob's devices | Anyone | `{ ikPk, opkPool[], pqspkPool[] }` |
| `@bob:groupInfo` | Bob's devices | Anyone | `{ externalHpkePk, externalKemPk, epoch }` |
| `@bob:keypackage.<deviceId>` | Enrolling device | Anyone | MLS KeyPackage (consumed on Add) |
| `@bob:inbox.<hash>` | **Alice's devices** | Bob's devices (E2E) | Cross-actor ciphertext |
| `@bob:mls.commit.<epoch>` | Bob's devices | Bob's devices (E2E) | TreeKEM Commit |
| `@bob:mls.welcome.<deviceId>` | Bob's devices | Target device (E2E) | PQXDH Welcome |

**Metadata leak (unavoidable):** server sees who talks to whom, frequency, timing, group membership list.

---

## Three Ratchets — Full Picture

| Ratchet | Intra-group | Cross-actor | Rotates | Mechanism |
|---|---|---|---|---|
| **1st — Symmetric** | ✅ Secret Tree | ⚠️ Chain from PQXDH | Per message | HKDF one-way chain, delete after use |
| **2nd — DH/KEM** | ✅ TreeKEM Update | ✅ XWing.encaps(externalHpkePk) bilateral | Per Commit (auto on reply) | X-Wing KEM, both sides contribute |
| **3rd — PQ KEM** | ✅ externalKemSk | ✅ MLKem.encaps(externalKemPk) bilateral | Per Commit | ML-KEM-768, independent PQ assumption |

---

## Security Scorecard vs Triple Ratchet

| Property | Triple Ratchet | This Design |
|---|---|---|
| Per-message FS (intra-group) | ✅ | ✅ Secret Tree |
| Per-message FS (cross-actor) | ✅ | ⚠️ Chain from PQXDH (device-bound) |
| PCS / DH ratchet | ✅ automatic per turn | ✅ automatic on reply (commit-gated) |
| PQ KEM ratchet | ✅ | ✅ X-Wing + ML-KEM |
| Post-quantum | ✅ ML-KEM | ✅ X-Wing everywhere |
| N-party | ❌ bilateral only | ✅ O(log N) Commits |
| Deniability (content) | ✅ | ✅ HMAC not signature |
| Deniability (group ops) | ✅ | ❌ ML-DSA signed Commits |
| Transport FS | TLS | TLS |

**Estimated coverage: ~90% of Triple Ratchet security.**

Remaining 10%:
- Cross-actor symmetric ratchet is device-bound, not identity-bound
- Group operation deniability structurally impossible with MLS accountability model
- Commit still requires a reply to trigger (not instantaneous like Signal's DH step)
