# pq_chat — Architecture

Single-file demo of the Triple Ratchet (Signal Double Ratchet + post-quantum KEM ratchet). This doc walks the algorithm from primitives upward. The trace produced by `bin/demo.dart` mirrors this structure section-for-section.

---

## Read this first

The Triple Ratchet is **one root-key chain advanced by three different inputs**, not three parallel state machines.

```
rootKey₀ → rootKey₁ → rootKey₂ → rootKey₃ → ...
            ▲           ▲           ▲
       chain step    DH step    KEM step
       (HMAC)        (X25519)   (ML-KEM)
```

Each arrow is **the same primitive** (`HKDF-SHA256`) advancing the chain. What differs is the *fresh entropy source* mixed in.

| Input source | When mixed | Defends against |
|---|---|---|
| chain key step (HMAC on `chain_key`) | every message | Forward secrecy *within* a chain |
| DH output (X25519) | peer's `dhPk` changed | Post-compromise security vs **classical** attacker |
| KEM ss (ML-KEM-768) | every N sent messages | Post-compromise security vs **post-quantum** attacker |

---

## Vocabulary

| Term | Meaning |
|---|---|
| **IK** | Identity Key (X25519 + Ed25519). Long-lived. |
| **SPK** | Signed Pre-Key (X25519 + ML-KEM). Medium-lived. Signed by Ed25519 IK. |
| **eph** | Ephemeral. One-shot keypair, discarded after one use. |
| **KEM** | Key Encapsulation Mechanism. Here: ML-KEM-768. |
| **encaps / decaps** | KEM operations. `Encaps(pk) → (ct, ss)`. `Decaps(sk, ct) → ss`. |
| **ss** | Shared Secret. 32 B output of DH or KEM. |
| **rootKey** (RK) | 32 B trunk of the KDF tree. Mutated only on ratchet steps. |
| **sendCK / recvCK** | 32 B chain keys per direction. Mutated every message. |
| **msg_key** (MK) | 32 B AES-GCM key for one message. Derived from CK. |
| **initiator / responder** | The party that runs PQXDH first / the party that reconstructs on first message. |

---

## Building blocks

### X25519 (classical DH)

| | |
|---|---|
| Use | Identity DH, SPK DH, ephemeral DH, every DH ratchet step |
| PK / SK / ss | 32 / 32 / 32 B |
| PQ-safe? | **No** (broken by Shor's algorithm on a quantum computer) |

### ML-KEM-768 (Kyber, post-quantum KEM)

| | |
|---|---|
| Use | SPK KEM in PQXDH init, KEM ratchet steps |
| PK / SK / ct / ss | 1184 / 2400 / 1088 / 32 B |
| SK layout | `s_bytes (1152) ‖ pk (1184) ‖ H(pk) (32) ‖ z (32)` |
| PQ-safe? | **Yes** (Module-LWE hardness) |

### Ed25519 (signing)

| | |
|---|---|
| Use | Identity signing key signs the SPK |
| PK / SK / signature | 32 / 32 / 64 B |

### HKDF-SHA256 (mixer)

| Use | Salt | IKM | info | Output |
|---|---|---|---|---|
| PQXDH init | empty | `dh1 ‖ dh2 ‖ dh3 ‖ kem_ss` (128 B) | `"pq-chat-init"` | 32 B (rootKey only) |
| Any ratchet step | current rootKey | fresh DH output **or** KEM ss | `"pq-chat-ratchet"` | 64 B (newRootKey ‖ newChainKey) |

### HMAC-SHA256 (chain key step)

| | |
|---|---|
| `HMAC(chain_key, 0x01)` | → `msg_key` |
| `HMAC(chain_key, 0x02)` | → next chain_key |

The constants `0x01` and `0x02` are just domain separators — any two distinct values would work.

### AES-256-GCM

| | |
|---|---|
| Key | 32 B |
| Nonce | 12 B (random per message) |
| MAC tag | 16 B |
| Ciphertext | length = plaintext (no padding) |

---

## Protocol walkthrough

Each section below corresponds to a labeled block in the `bin/demo.dart` trace.

### 1. Setup — generate identities

Each party generates three long-lived keypairs + one signature:

```
ikDh   = X25519.newKeyPair()
ikSig  = Ed25519.newKeyPair()
spkDh  = X25519.newKeyPair()                         (medium-lived)
spkKem = ML-KEM-768.generateKeyPair()                (medium-lived)
sig    = Ed25519.sign(ikSig.sk, spkDh.pk)            (signs the SPK)
```

The **PreKeyBundle** published by each party = `{ikDh.pk, ikSig.pk, spkDh.pk, spkKem.pk, sig}`.

### 2. SPK signature verification

Before using a peer's bundle, the local party verifies:

```
Ed25519.verify(peer.ikSig.pk, peer.spkDh.pk, peer.sig)  →  true / false
```

If false, abort. If true, the peer's identity has cryptographically endorsed the SPK they're publishing.

### 3. PQXDH handshake (initiator)

```
1. eph = X25519.newKeyPair()                          fresh ephemeral
2. dh1 = X25519(initiator.ik.sk × responder.spk.pk)   binds initiator ident to responder spk
3. dh2 = X25519(initiator.ik.sk × responder.ik.pk)    binds the two identities
4. dh3 = X25519(initiator.eph.sk × responder.spk.pk)  binds initiator freshness to responder spk
5. (initKemCt, kem_ss) = ML-KEM.Encaps(responder.spk_kem.pk)
6. rootKey₀ = HKDF(ikm = dh1 ‖ dh2 ‖ dh3 ‖ kem_ss, info = "pq-chat-init")
7. dhRatchet = X25519.newKeyPair()                    initiator's first ratchet keypair
8. dhOut = X25519(dhRatchet.sk × responder.spk.pk)    first DH ratchet step
9. rootKey₁, sendCK = HKDF-RK-step(rootKey₀, dhOut)
10. kemRatchet = ML-KEM.generateKeyPair()             initiator's first KEM ratchet keypair
```

**The initiator's first message carries:** `initEphPk`, `initIkPk`, `initKemCt`, `dhRatchet.pk`, and `kemRatchet.pk`. These let the responder reconstruct everything.

### 4. PQXDH respond (responder, on first incoming message)

Mirror the initiator's math — substitute *responder.sk × initiator.pk* for each DH. By X25519 symmetry, the outputs are identical:

```
1. dh1 = X25519(responder.spk.sk × msg.initIkPk)      ≡ initiator's dh1
2. dh2 = X25519(responder.ik.sk  × msg.initIkPk)      ≡ initiator's dh2
3. dh3 = X25519(responder.spk.sk × msg.initEphPk)     ≡ initiator's dh3
4. kem_ss = ML-KEM.Decaps(responder.spk_kem.sk, msg.initKemCt)
5. rootKey₀ = HKDF(ikm = dh1 ‖ dh2 ‖ dh3 ‖ kem_ss, info = "pq-chat-init")
6. dhOut1 = X25519(responder.spk.sk × msg.dhPk)       mirrors initiator's first DH step
7. rootKey₁, recvCK = HKDF-RK-step(rootKey₀, dhOut1)
8. responder.dhRatchet = X25519.newKeyPair()          responder's own first ratchet keypair
9. dhOut2 = X25519(responder.dhRatchet.sk × msg.dhPk)
10. rootKey₂, sendCK = HKDF-RK-step(rootKey₁, dhOut2)
```

**After PQXDH:**

| Field | Initiator | Responder |
|---|---|---|
| `rootKey` | rootKey₁ | rootKey₂ |
| `sendCK` | derived in step 9 | derived in step 10 |
| `recvCK` | not yet set | matches initiator's sendCK |
| `dhRatchet keypair` | initiator's | responder's (different) |

**The asymmetry resolves on the first round-trip:** when initiator receives responder's first reply, it performs a DH ratchet step that gets it to `rootKey₂`.

### 5. Sending a message (steady state)

```
if sendN > 0 and sendN % kemRatchetEvery == 0 and remoteKemPk != null:
    # ── KEM ratchet step ──
    (kemCt, kem_ss) = ML-KEM.Encaps(remoteKemPk)
    rootKey         = HKDF-RK-step(rootKey, kem_ss)[0:32]   # discard the ck half
    kemRatchet      = ML-KEM.generateKeyPair()              # rotate own keypair
    advertise kemCt + new kemPk on the wire

# ── symmetric chain step ──
msg_key, new_sendCK = HMAC(sendCK, 0x01), HMAC(sendCK, 0x02)
sendCK              = new_sendCK

# ── AES-256-GCM seal ──
nonce          = random(12)
(ct, mac)      = AES-256-GCM.Seal(msg_key, nonce, plaintext)
```

**Wire envelope:** `{ dhPk, [kemPk], [kemCt], nonce, ct, mac, msgN, isInit, [init payload] }`.

Bracketed fields are optional. `dhPk` always present (sender's current DH ratchet PK). `kemPk` + `kemCt` present only when this message is a KEM ratchet step (or the first message advertising the initial kemPk).

### 6. Receiving a message (steady state)

```
if msg.dhPk != local remoteDhPk:
    # ── DH ratchet step ──
    dhOut1     = X25519(my.dhRatchet.sk × msg.dhPk)
    rootKey, recvCK = HKDF-RK-step(rootKey, dhOut1)
    my.dhRatchet    = X25519.newKeyPair()                  # rotate own keypair
    dhOut2     = X25519(my.dhRatchet.sk × msg.dhPk)
    rootKey, sendCK = HKDF-RK-step(rootKey, dhOut2)
    remoteDhPk = msg.dhPk
    sendN = recvN = 0                                       # chains reset

if msg.kemCt != null:
    # ── KEM ratchet receive ──
    kem_ss   = ML-KEM.Decaps(my.kemRatchet.sk, msg.kemCt)
    rootKey  = HKDF-RK-step(rootKey, kem_ss)[0:32]
    if msg.kemPk: remoteKemPk = msg.kemPk
    my.kemRatchet = ML-KEM.generateKeyPair()

# ── symmetric chain step ──
msg_key, new_recvCK = HMAC(recvCK, 0x01), HMAC(recvCK, 0x02)
recvCK              = new_recvCK

# ── AES-256-GCM open ──
plaintext = AES-256-GCM.Open(msg_key, msg.nonce, msg.ct, msg.mac)
```

### 7. The trigger order matters

If a KEM ratchet attempts to fire **before the first DH-ratchet round-trip** has completed, initiator and responder will have unequal `rootKey`s (rk₁ vs rk₂ above). Mixing the same `kem_ss` into both produces *different* outputs, desynchronizing the chain.

The demo's scripted scenario completes one round-trip first (alice send → bob send → alice receives bob's reply → DH ratchet fires) before any KEM ratchet attempt. In a real chat, this happens naturally because the first round-trip arrives long before message #N triggers the KEM threshold.

---

## State per peer (what to persist)

| State | Persisted? | Why |
|---|---|---|
| `rootKey` | yes | Survives across runs; ratchet trunk |
| `sendCK`, `recvCK` | yes | One per direction per session |
| Current `dhRatchet` keypair | yes | Rotates on DH ratchet step |
| Current `kemRatchet` keypair | yes | Rotates on KEM ratchet step |
| `remoteDhPk`, `remoteKemPk` | yes | Needed to detect "new" peer keys |
| `sendN`, `recvN`, `msgsSinceKem` | yes | Drive ratchet triggers |
| `msg_key`, `chain_key intermediate`, `pq_ss`, `classical_ss` | **no** | Forward secrecy — must vanish |

**atProtocol mapping for production:** the entire per-peer state lives as **one private atKey** in the local keystore (e.g., `ratchet_state.<peer>.pqchat@<self>`). Never published, never sent. Identity + SPK bundle is **one published atKey** (`prekeybundle.pqchat@<self>`), rotated on a schedule (weekly or so).

---

## What this demo deliberately omits

- **Persistence.** State lives in `main`'s locals; re-runs start from scratch.
- **Skipped message keys / out-of-order delivery.** Messages here are delivered strictly in order. Production needs a bounded LRU of skipped `msg_key`s.
- **The file-based two-terminal transport** from earlier iterations.
- **Network MITM defense** — TOFU on bundles; production needs out-of-band identity verification (atProtocol enrollment, QR scan, etc.).
- **Side-channel resistance** — Dart provides no constant-time guarantees beyond what `cryptography`/`pqcrypto` give.

---

## Mapping the demo to production atProtocol

| Demo concept | atProtocol equivalent |
|---|---|
| `Identity.ikDh.pk` (X25519) | `publickey.dh.pqchat@<self>` |
| `Identity.ikSig.pk` (Ed25519) | `publickey.signing.pqchat@<self>` |
| Full PreKeyBundle | `prekeybundle.pqchat@<self>` (single atKey, value = JSON envelope) |
| Per-peer ratchet state | `ratchet_state.<peer>.pqchat@<self>` (private, local keystore only) |
| `WireMessage` (one envelope) | One `notify:` payload — value carries `dhPk` + ct + nonce + mac + optional KEM fields |
| Sender's encaps to recipient's KEM PK | Sender's `plookup:publickey.mlkem.pqchat@<peer>` then encaps in memory |
| Recipient's monitor stream picks up notification | Demo's polling loop equivalent (omitted in this single-file version) |
