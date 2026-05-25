# PQ Compliance — Component Architecture

**Status: Draft.** Nothing in this file is locked. All component names, package boundaries, suite IDs, and stage assignments are working proposals to be discussed and revised.

Full set of components needed for atProtocol to become end-to-end post-quantum compliant. Aligns with the three goals in issue [#1893](https://github.com/atsign-foundation/at_client_sdk/issues/1893).

Each component below has a purpose, a mechanism diagram, and the package(s) that own it. A unified block diagram at the end shows how they compose.

Related drafts in this directory: [`algorithms-and-protocols.md`](algorithms-and-protocols.md) (algorithms/protocols catalog), [`crypto-fundamentals.md`](crypto-fundamentals.md) (mental model for ML-KEM's role), [`native-dependencies.md`](native-dependencies.md) (native dep candidates), [`pqxdh-spqr-deep-dive.md`](pqxdh-spqr-deep-dive.md) (Goal B deep dive — threat model, prekey bundles, ratchet state, wire formats).

---

## The three goals (from issue #1893)

| Goal | Name | What it gives us | Status / stage | Specs |
|---|---|---|---|---|
| **A** | **Hybrid classical + PQ KEM** | Replace RSA-OAEP key-wrap with X25519 ‖ ML-KEM-768 so an attacker recording today's traffic can't decrypt it once quantum computers exist (defeats "harvest now, decrypt later"). Static `shared_key.<peer>@me` objects become PQ-safe. | **Stage 1 + 2** (Track 1, this plan) | [FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) (ML-KEM), [RFC 7748](https://datatracker.ietf.org/doc/html/rfc7748) (X25519), [draft-ietf-tls-hybrid-design](https://datatracker.ietf.org/doc/draft-ietf-tls-hybrid-design/) (hybrid construction) |
| **B** | **Signal SPQR — Sparse Post-Quantum Ratchet** (built on PQXDH session init) | Per-session **forward secrecy** and **post-compromise security** for streamed messages between two atSigns. Each message uses a fresh key; old keys are deleted; key compromise heals on the next ratchet step. PQ-resistant version of Signal's Double Ratchet. **Requires PQXDH** for PQ-safe session initialization (Component 12). | Stage 3 | [Signal SPQR announcement (2025)](https://signal.org/blog/spqr/), [PQXDH spec](https://signal.org/docs/specifications/pqxdh/) |
| **C** | **PQ-MLS — `draft-ietf-mls-combiner`** | Group messaging analogue of B: shared group key with PQ guarantees, scales O(log N) for member adds/removes/rekeys. Needed for any multi-party atProtocol surface (group chat, shared collections, multi-device). | Stage 4 | [draft-ietf-mls-combiner](https://datatracker.ietf.org/doc/draft-ietf-mls-combiner/), [RFC 9420 (MLS base)](https://datatracker.ietf.org/doc/html/rfc9420) |

**Why all three, not just A:** Goal A protects static keys at rest. It does **not** give forward secrecy — if a peer's private key leaks tomorrow, every message encrypted under shared keys derived from it is exposed. SPQR (B) plugs that hole for 1:1 streams. PQ-MLS (C) does the same for groups. The three goals are layered, not alternatives.

---

## Component inventory

| # | Component | Goal A | Goal B | Goal C | Owner package |
|---|---|:--:|:--:|:--:|---|
| 1 | Hybrid KEM (key wrap) | ✓ | | | `at_chops` + `at_chops_pq_native` |
| 2 | Hybrid Signatures (PKAM auth) | future | | | `at_chops` + `at_chops_pq_native` |
| 3 | Identity & `.atKeys` schema | ✓ | ✓ | ✓ | `at_auth` |
| 4 | Public key directory & verbs | ✓ | ✓ | ✓ | atServer + `at_client` |
| 5 | Capability & suite negotiation | ✓ | ✓ | ✓ | `at_client` + atServer `from:` |
| 6 | Wire envelope format | ✓ | ✓ | ✓ | `at_protocol` / `at_commons` |
| 7 | Forward-secret session ratchet (SPQR) | | ✓ | | new `at_pq_ratchet` (Stage 3) |
| 8 | Group ratchet (PQ-MLS) | | | ✓ | new `at_pq_mls` (Stage 4) |
| 9 | Native FFI backend | ✓ | ✓ | ✓ | `at_chops_pq_native` |
| 10 | Trust-on-first-PQ & downgrade defense | ✓ | ✓ | ✓ | `at_client` |
| 11 | Key migration & rotation | ✓ | ✓ | ✓ | `at_auth` + `at_client` |
| 12 | PQXDH — session initialization | | ✓ | | new `at_pq_ratchet` (Stage 3) |

---

## 1. Hybrid KEM — key wrap

Replaces RSA-OAEP wrap of the per-conversation AES shared key.

```mermaid
flowchart LR
  subgraph Sender
    K[AES-256 shared_key<br/>32B] --> H[Hybrid KEM Wrap]
    XP1[eph X25519 sk] --> H
    PEER_X[peer X25519 pk] --> H
    PEER_K[peer ML-KEM pk] --> H
  end
  H --> ENV["Envelope:<br/>ver‖suite‖eph_pk‖pq_ct‖nonce‖ct‖tag<br/>1182 B"]
  ENV --> U[Hybrid KEM Unwrap]
  subgraph Receiver
    SX[self X25519 sk] --> U
    SK[self ML-KEM sk] --> U
    U --> K2[AES-256 shared_key<br/>32B recovered]
  end

  classDef op fill:#1565c0,stroke:#0d47a1,color:#ffffff
  classDef envelope fill:#c62828,stroke:#b71c1c,color:#ffffff
  class H,U op
  class ENV envelope
```

**Algorithms:** X25519 (RFC 7748) ‖ ML-KEM-768 (FIPS 203) → HKDF-SHA256 (RFC 5869) → AES-256-GCM (NIST SP 800-38D).

---

## 2. Hybrid Signatures — PKAM authentication

Replaces RSA-PKAM with hybrid Ed25519 + ML-DSA-65. Track 1 leaves this alone; this is Stage 5 (the renamed Track 2).

```mermaid
flowchart LR
  CH[challenge from atServer] --> S1[Ed25519.sign sk_classical]
  CH --> S2[ML-DSA-65.sign sk_pq]
  S1 --> CONCAT["sig = ed25519_sig ‖ mldsa_sig"]
  S2 --> CONCAT
  CONCAT --> V[atServer verify]
  V --> V1[Ed25519.verify pk_classical]
  V --> V2[ML-DSA-65.verify pk_pq]
  V1 -->|AND| OK[both must pass]
  V2 -->|AND| OK
```

**Why concatenation, not OR:** if either component is broken, the strong one still authenticates. NIST PQC hybrid signature guidance.

---

## 3. Identity & `.atKeys` schema

Each atSign keeps several long-term keypairs. Schema extends, never replaces, existing fields.

```mermaid
classDiagram
  class AtKeys {
    +AtBytes apkamPublicKey       %% classical PKAM (RSA today)
    +AtBytes apkamPrivateKey
    +AtBytes defaultEncryptionPublicKey   %% RSA-OAEP encrypt (legacy)
    +AtBytes defaultEncryptionPrivateKey
    +AtBytes defaultSelfEncryptionKey     %% AES-256
    +AtBytes pqEncryptPublicKey  %% NEW: X25519_pk ‖ MLKEM_pk
    +AtBytes pqEncryptPrivateKey %% NEW: X25519_sk ‖ MLKEM_sk
    +AtBytes pqSignPublicKey     %% Stage 5: Ed25519_pk ‖ MLDSA_pk
    +AtBytes pqSignPrivateKey    %% Stage 5
    +int pqVersion               %% suite generation
    +Map metadata
  }
```

**Persistence:** same `~/.atsign/keys/<atsign>_key.atKeys` file, JSON-serialized, AES-CTR encrypted with the Argon2id-derived passphrase key. No file location change.

---

## 4. Public key directory & verbs

atServer must serve every flavor of public key. Existing `lookup:publickey.<atsign>` returns RSA; new verbs return PQ blobs.

```mermaid
sequenceDiagram
  participant C as at_client
  participant S as atServer (own)
  participant P as atServer (peer)

  Note over C,S: Publish at first run
  C->>S: update:pq_publickey.@me = X25519_pk ‖ MLKEM_pk
  C->>S: update:pq_signpublickey.@me = Ed_pk ‖ MLDSA_pk

  Note over C,P: Resolve peer key
  C->>P: lookup:pq_publickey.@bob
  P-->>C: X25519_pk ‖ MLKEM_pk  (or 'absent')
  C->>C: cache as cached:public:pq_publickey.@bob
```

**Storage at server:** ordinary keystore entries with public scope. **Negotiation hint:** `from:` response advertises `"pq": ["mlkem768_x25519_v1", ...]`.

---

## 5. Capability & suite negotiation

Both parties must agree on a suite before they wrap or sign. Uses an explicit registry, not version inference.

```mermaid
flowchart TD
  A["at_client wants to wrap for @peer"] --> Q1{peer pq_publickey<br/>cached/fetchable?}
  Q1 -- no --> Q2{TOFP record says<br/>peer was PQ before?}
  Q2 -- yes --> WARN[log pq.downgrade.suspected]
  Q2 -- no  --> FALL[RSA fallback path]
  WARN --> FALL
  Q1 -- yes --> Q3{local at_chops<br/>supports suite?}
  Q3 -- no  --> FALL
  Q3 -- yes --> PICK[pick highest mutually-supported suite]
  PICK --> WRAP["Hybrid wrap, tag enc:ver‖suite"]
```

**Suite IDs (proposed registry):**
| ID | Suite |
|---|---|
| `0x01` | `MLKEM768_X25519_HKDF_SHA256_AESGCM256` |
| `0x02` | `MLKEM1024_X25519_HKDF_SHA512_AESGCM256` (future) |

---

## 6. Wire envelope format

A single self-describing byte layout for every wrapped object. Parsable without context: first 2 bytes always tell you version + suite.

```mermaid
flowchart LR
  V[ver<br/>1B] --> S[suite<br/>1B] --> H["header (suite-specific):<br/>e.g. eph_X25519_pk‖pq_ct<br/>32+1088 = 1120B"] --> N[nonce<br/>12B] --> P["AEAD ct+tag<br/>(payload size + 16)"]
```

**Property:** `ver` covers parser breaks (e.g., adding a 4-byte AAD-length prefix later). `suite` covers crypto changes within the same wire schema. They are intentionally separate axes of evolution.

---

## 7. Forward-secret session ratchet — SPQR (Goal B)

Signal's SPQR is a **triple ratchet** — symmetric chain + classical DH ratchet + sparse PQ KEM ratchet — that runs *after* a session has been established via PQXDH (Component 12). It provides forward secrecy and post-compromise security for streamed messages between two atSigns.

```mermaid
sequenceDiagram
  participant A as alice
  participant B as bob
  Note over A,B: Component 12 (PQXDH) has already established<br/>a shared root_key. SPQR takes it from there.

  loop Per message (cheap)
    A->>A: KDF chain_key_send → msg_key
    A->>A: fresh X25519 eph (classical DH ratchet)
    A->>B: enc(msg_key, message) + X25519 eph pk
    B->>B: KDF chain_key_recv → msg_key
    B->>B: dec(msg_key, message)
    Note over A,B: Old keys deleted → forward secrecy
  end

  Note over A,B: Sparse KEM ratchet (every N msgs / T sec)
  A->>B: ML-KEM encaps ct (≈1 KB)
  B->>A: ack
  Note over A,B: Mix PQ ss into root_key → new chain_keys<br/>= post-compromise security against quantum adversary
```

**Why "sparse":** ML-KEM ciphertexts are ~1 KB. Running KEM per message tanks mobile bandwidth/battery. SPQR runs DH every message (cheap) and KEM periodically (expensive but amortized). PQ entropy still mixes into the root_key, so PQ guarantees propagate across the sparse boundaries.

**Position in atProtocol:** notification/stream payloads (chat, presence, real-time). NOT for static shared keys — those stay on Component 1.

**Dependency:** Component 12 (PQXDH) must produce the initial `root_key`. Without PQ session-init, SPQR's PQ guarantees collapse — see [`crypto-fundamentals.md`](crypto-fundamentals.md) for the mental model, §12 below for the architectural role, and [`pqxdh-spqr-deep-dive.md`](pqxdh-spqr-deep-dive.md) for the full state machine and wire formats.

---

## 8. Group ratchet — PQ-MLS (Goal C)

`draft-ietf-mls-combiner` defines a PQ variant of MLS. Group secret tree where each node combines classical + PQ KEM. Stage 4 work.

```mermaid
flowchart TB
  ROOT[group root secret]
  ROOT --> L1A[subtree A]
  ROOT --> L1B[subtree B]
  L1A --> M1[alice leaf<br/>hybrid KEM pk]
  L1A --> M2[bob leaf<br/>hybrid KEM pk]
  L1B --> M3[carol leaf<br/>hybrid KEM pk]
  L1B --> M4[dan leaf<br/>hybrid KEM pk]

  NEW[new member 'eve'] -.->|Welcome msg<br/>hybrid-wrapped subtree path| L1B
```

**Why MLS-combiner instead of n-pairwise SPQR:** MLS scales O(log N) for adds/removes and key rotation in a group of N. SPQR is O(N).

---

## 9. Native FFI backend

The only home for non-Dart code in this work. Two PQ schemes via the same plugin.

```mermaid
flowchart LR
  subgraph DartSide
    API[at_chops_pq_native<br/>public Dart API]
    BIND[bindings.dart<br/>ffigen]
  end
  subgraph CSide
    SHIM[at_pq_shim.c/.h]
    KEM[mlkem-native<br/>ML-KEM-768]
    DSA[mldsa-native<br/>ML-DSA-65<br/>Stage 5]
  end
  API --> BIND --> SHIM
  SHIM --> KEM
  SHIM --> DSA

  classDef dart fill:#1565c0,stroke:#0d47a1,color:#ffffff
  classDef cnative fill:#2e7d32,stroke:#1b5e20,color:#ffffff
  class API,BIND dart
  class SHIM,KEM,DSA cnative
```

**Build artifacts:** per-platform static lib (.a/.so/.dll). **Web:** not in scope — needs Emscripten WASM build (Stage future).

---

## 10. Trust-on-first-PQ & downgrade defense

A passive MITM can strip `lookup:pq_publickey` responses, silently downgrading. Defense is per-peer persistence + observability.

```mermaid
stateDiagram-v2
  [*] --> Unknown
  Unknown --> PqSeen: pq_publickey lookup returned key
  Unknown --> RsaOnly: pq_publickey lookup absent
  RsaOnly --> PqSeen: later lookup returns key
  PqSeen --> PqSeen: lookup returns key — normal
  PqSeen --> Downgrade: pq_publickey now absent
  Downgrade --> Downgrade: log pq.downgrade.suspected — wrap with RSA fallback
  Downgrade --> PqSeen: lookup returns key again
```

**Storage:** local SQLite/keystore record `{peer_atsign → first_pq_seen_at}`. **Stage 1 policy:** log only. **Future:** refuse fallback once `PqSeen` is reached, after PQ coverage stabilises.

---

## 11. Key migration & rotation

Two distinct flows: first-time PQ generation, and periodic rotation. Both must keep old keys readable to decrypt historical data.

```mermaid
flowchart TD
  subgraph FirstRun[First post-upgrade run]
    L[load .atKeys] --> C{pqVersion present?}
    C -- no --> G[generate hybrid KEM keypair]
    G --> P[persist .atKeys with pqVersion=1]
    P --> PUB[publish pq_publickey to atServer]
  end
  subgraph Rotation[Periodic rotation]
    T[rotation trigger:<br/>scheduled / suite bump / compromise] --> GNEW[generate new hybrid keypair]
    GNEW --> KEEP[keep old sk indexed by pqVersion<br/>for historical decrypt]
    GNEW --> PNEW[persist new sk as current]
    PNEW --> PUB2[publish new pq_publickey]
    PUB2 --> RWRAP[rewrap shared_keys with new wrap_key over time]
  end
```

**Compromise recovery:** out of scope for Track 1 — flagged as Stage 5 follow-up.

---

## 12. PQXDH — post-quantum session initialization (Goal B prerequisite)

Signal's PQXDH (Post-Quantum Extended Diffie-Hellman) is the **session-init** companion to SPQR. It produces the initial `root_key` that SPQR (Component 7) ratchets forward from. Without PQXDH (or an equivalent PQ key agreement at session start), SPQR ratchets from classically-bootstrapped secrets — fatal under harvest-now-decrypt-later.

PQXDH solves three problems simultaneously:

| Problem | How PQXDH addresses it |
|---|---|
| PQ-safe key agreement at session start | Hybrid X25519 + ML-KEM KEM (same primitive as Goal A) |
| Asynchronous delivery — alice can send to offline bob | Prekey bundle published to atServer in advance |
| Identity binding & deniability | Long-term identity key signs the prekey bundle |

```mermaid
sequenceDiagram
  participant A as alice
  participant S as atServer (bob's)
  participant B as bob

  Note over B,S: Once at registration, periodically refreshed
  B->>S: publish PreKeyBundle:<br/>identity_pk, signed_prekey, signature,<br/>one_time_prekey, kem_prekey

  Note over A,B: Alice initiates session, bob may be offline
  A->>S: fetch PreKeyBundle.@bob
  S-->>A: bundle
  A->>A: verify signature over signed_prekey
  A->>A: classical DH: X25519(eph_a_sk, identity_pk)<br/>+ X25519(eph_a_sk, signed_prekey)<br/>+ X25519(eph_a_sk, one_time_prekey)
  A->>A: PQ KEM: ML-KEM.Encaps(kem_prekey) → (ct, ss_pq)
  A->>A: root_key = HKDF(all_dh_secrets ‖ ss_pq)
  A->>S: send InitialMessage:<br/>eph_a_pk, ct, AEAD(root_key, first_payload)
  S-->>B: deliver when online
  B->>B: same DH + ML-KEM.Decaps(sk, ct) → identical root_key
  B->>B: decrypt first payload
  Note over A,B: SPQR (Component 7) takes over from here
```

**Why this is its own component and not part of Component 7:** PQXDH runs **once per session** at the start; SPQR runs **per message** for the lifetime of the session. Different cadences, different state, different code paths. Signal documents them as a matched pair for exactly this reason — their security proofs are joint.

**Could we substitute Goal A's hybrid KEM directly?** The cryptographic primitive is the same. But PQXDH adds the **prekey-bundle** protocol layer (async delivery + identity binding) which Goal A's static `shared_key.<peer>@me` flow doesn't need. atProtocol notifications are async, so we'd need that layer either way — adopting PQXDH wholesale (vs reinventing) is the working proposal; not yet decided.

**Storage at atServer:** new keystore entries for each atSign:
- `public:pq_signed_prekey.@me` (rotated periodically)
- `public:pq_one_time_prekeys.@me` (consumed on use, replenished by client)
- `public:pq_kem_prekey.@me`

---

## Unified block diagram

Split into two views to keep the labels legible. Diagram 1 shows the per-device component stack; Diagram 2 shows the wire interactions between devices and atServers. Both sides (alice / bob) mirror Diagram 1 — drawing it once is sufficient.

### 1. Per-device component stack

```mermaid
flowchart TB
  APP[App code] --> AC[at_client]
  AC --> ENC[EncryptionService]
  ENC --> KEYS[".atKeys cache (C3)"]
  ENC --> CAP["Suite negotiation (C5)"]
  CAP --> TOFP["TOFP cache (C10)"]
  ENC --> CHOPS[at_chops]
  CHOPS --> KEM["Hybrid KEM (C1)"]
  CHOPS --> SIG["Hybrid Signatures (C2)"]
  CHOPS --> PQXDH["PQXDH session init (C12)"]
  CHOPS --> SPQR["SPQR ratchet (C7)"]
  CHOPS --> MLS["PQ-MLS (C8)"]
  PQXDH --> SPQR
  KEM --> PQN["at_chops_pq_native (C9)"]
  SIG --> PQN
  PQXDH --> PQN
  SPQR --> PQN
  MLS --> PQN
  PQN --> FFI[("mlkem-native FFI<br/>mldsa-native FFI")]
  ENC --> ENV["Envelope codec (C6)"]
  ENV --> AC

  classDef goalA fill:#2e7d32,stroke:#1b5e20,color:#ffffff
  classDef goalB fill:#1565c0,stroke:#0d47a1,color:#ffffff
  classDef goalC fill:#c62828,stroke:#b71c1c,color:#ffffff
  classDef shared fill:#455a64,stroke:#263238,color:#ffffff
  class KEM,KEYS goalA
  class PQXDH,SPQR goalB
  class MLS goalC
  class PQN,FFI,ENV,CAP,TOFP,SIG,CHOPS,ENC shared
```

### 2. Cross-device wire flow

```mermaid
flowchart LR
  subgraph alice[alice device]
    ASTACK[at_client + at_chops<br/>pq_native + FFI]
  end
  subgraph aliceSrv[alice's atServer]
    AKEYS_S["@me keys:<br/>pq_publickey<br/>pq_signpublickey<br/>prekey bundle"]
  end
  subgraph bobSrv[bob's atServer]
    BKEYS_S["@me keys:<br/>pq_publickey<br/>pq_signpublickey<br/>prekey bundle<br/>shared_key.@alice"]
  end
  subgraph bob[bob device]
    BSTACK[at_client + at_chops<br/>pq_native + FFI]
  end

  ASTACK -->|publish own keys, prekeys| AKEYS_S
  ASTACK -->|lookup peer keys & prekey bundle| BKEYS_S
  ASTACK -->|update shared_key.@bob| BKEYS_S
  BKEYS_S -->|lookup shared_key.@alice| BSTACK
  BSTACK -->|publish own keys, prekeys| BKEYS_S

  classDef device fill:#455a64,stroke:#263238,color:#ffffff
  classDef server fill:#37474f,stroke:#263238,color:#ffffff
  class ASTACK,BSTACK device
  class AKEYS_S,BKEYS_S server
```

**Color legend** (Diagram 1):
- **Green** = Goal A (Track 1, hybrid KEM key wrap)
- **Blue** = Goal B (Stage 3, SPQR + PQXDH)
- **Red** = Goal C (Stage 4, PQ-MLS)
- **Slate** = Shared infrastructure (envelope, FFI, suite negotiation, TOFP, signatures, at_chops, EncryptionService)

---

## Order of construction (what blocks what)

```mermaid
flowchart LR
  N[9. Native FFI<br/>mlkem-native] --> K[1. Hybrid KEM wrap]
  N --> S[2. Hybrid Signatures]
  E[6. Envelope format] --> K
  E --> S
  R[5. Suite registry] --> E
  K --> ID[3. .atKeys schema]
  K --> D[4. PubKey directory verbs]
  D --> CAP[5. Negotiation]
  CAP --> T[10. TOFP]
  ID --> M[11. Migration]
  K --> PQXDH[12. PQXDH session init]
  D --> PQXDH
  PQXDH --> SPQR[7. SPQR ratchet]
  SPQR --> MLS[8. PQ-MLS]

  classDef stage1 fill:#2e7d32,stroke:#1b5e20,color:#ffffff
  classDef stage2 fill:#f9a825,stroke:#f57f17,color:#000000
  classDef stage3 fill:#1565c0,stroke:#0d47a1,color:#ffffff
  classDef stage4 fill:#c62828,stroke:#b71c1c,color:#ffffff
  class N,K,E,R stage1
  class ID,D,CAP,T,M stage2
  class PQXDH,SPQR,S stage3
  class MLS stage4
```

Critical path: **Native FFI (9) → Envelope (6) → Hybrid KEM (1) → PQXDH (12) → SPQR (7).** Goal C (PQ-MLS) reuses every primitive built for A + B; no new cryptographic primitives needed.
