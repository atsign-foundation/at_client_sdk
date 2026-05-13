# PQ Migration — Mechanisms, Protocols, Algorithms

**Status: Draft.** Nothing in this file is locked. Algorithm choices, suite IDs, package boundaries, and stage assignments are working proposals.

Catalog of moving parts for Track 1 (hybrid X25519 + ML-KEM-768 KEM replacing RSA-OAEP key-wrap). Cross-references `../pq-migration.md`.

Related drafts: [`components.md`](components.md), [`ML-KEM.md`](ML-KEM.md), [`dependencies.md`](dependencies.md).

> **Two-stage delivery (per issue #1893):** Stage 1 exercises the crypto in-process via an `Actor` harness — no atProtocol. Stage 2 wires the same API into `at_client` / atServer. Diagrams below mark which boxes light up at each stage.

---

## Algorithms

| Algorithm | Role | Spec | New / existing |
|---|---|---|---|
| ML-KEM-768 | PQ KEM — encaps/decaps 32 B shared secret | FIPS 203 | **new** (via liboqs) |
| X25519 | Classical ECDH — 32 B shared secret | RFC 7748 | **new** in this path (pointycastle has it) |
| HKDF-SHA256 | Extract + Expand for combiner | RFC 5869 | existing in `at_chops` |
| AES-256-GCM | AEAD wrap of the AES shared key | NIST SP 800-38D | existing primitive, new use |
| RSA-OAEP-2048 | Fallback wrap for non-PQ peers | RFC 8017 | existing — kept |
| AES-256-CTR | Bulk data symmetric encryption (unchanged) | — | existing |
| Argon2id | `.atKeys` passphrase KDF (unchanged) | RFC 9106 | existing |

## Mechanisms

| Mechanism | Purpose | Lives in |
|---|---|---|
| Hybrid KEM combiner | Bind classical + PQ shared secrets into one wrap key | `at_chops` (new dispatch path) |
| Capability negotiation | Decide hybrid vs RSA fallback per peer | `at_client` `EncryptionService` |
| Suite / version registry | Identify wire format + crypto suite per envelope | `at_protocol` (or `at_commons`) |
| Envelope tag in metadata | Receiver dispatches decrypt path on `enc:<ver><suite>` | shared-key entry metadata |
| `.atKeys` schema migration | Add hybrid keypair fields, generate on first load | `at_auth` keyfile I/O |
| FFI bridge to liboqs | Native ML-KEM-768 keypair/encaps/decaps | new `at_chops_pq_native` |
| Trust-on-first-PQ (TOFP) | Detect/log downgrade after a peer is once seen PQ-capable | `at_client` (new cache) |
| Fallback path | Reuse RSA-OAEP when peer or self lacks PQ | unchanged code path |

## Protocols (atProtocol-level additions)

| Verb / event | Direction | Purpose |
|---|---|---|
| `update:pq_publickey.<atsign>` | self → atServer | Publish hybrid pubkey blob (X25519 ‖ ML-KEM-768) |
| `lookup:pq_publickey.<atsign>` | client → atServer | Fetch peer's hybrid pubkey |
| `from:` response field `"pq": [...]` | atServer → client | Advertise supported suites |
| Shared-key envelope tag `enc:<ver><suite>` | metadata, both sides | Dispatch decrypt path |

---

## Component map

Solid borders = Stage 1 (in-process). Dashed borders = added in Stage 2 (atProtocol wiring).

```mermaid
flowchart LR
  subgraph App
    AC[at_client]
  end
  subgraph Crypto
    CH[at_chops]
    PQ[at_chops_pq_native<br/>NEW]
  end
  subgraph Auth
    AU[at_auth<br/>.atKeys schema bump]
  end
  subgraph Server
    AS[atServer<br/>pq_publickey verbs]
  end
  subgraph Native
    OQS[(mlkem-native<br/>ML-KEM-768)]
    PC[(pointycastle<br/>X25519)]
    DC[(dart:typed_data<br/>HKDF, AES-GCM)]
  end

  AC -->|encryptString hybrid| CH
  CH -->|encaps/decaps| PQ
  PQ -->|FFI| OQS
  CH -->|scalar mult| PC
  CH -->|KDF, AEAD| DC
  AU -->|load/save hybrid keys| CH
  AC -->|lookup:pq_publickey| AS
  AC -->|update:pq_publickey| AS

  classDef stage2 stroke-dasharray: 5 5,stroke:#888
  class AC,AU,AS stage2
```

## Stage 1 actor harness (in-process validation, no atProtocol)

Lives under `packages/at_chops_pq_native/test/actor_harness.dart`. Pure Dart driver; same crypto API that Stage 2 wires into `at_client`.

```mermaid
flowchart LR
  subgraph Process["Single Dart process — Stage 1 test harness"]
    A[Actor 'alice'<br/>hybridKeyPair_A]
    B[Actor 'bob'<br/>hybridKeyPair_B]
    BUS[("InMemoryBus<br/>alice.send to bob.fetch")]
    A -->|send wrapped AES_key| BUS
    BUS -->|fetch| B
  end
  A -.->|encryptHybrid| CH[at_chops]
  B -.->|decryptHybrid| CH
  CH --> PQ[at_chops_pq_native]
  PQ --> N[(mlkem-native FFI)]
```

Exit criterion for Stage 1: actor harness round-trips a wrapped AES key between alice/bob, hybrid KATs pass, mixed-suite (PQ ↔ RSA-fallback) actor pairs interop. No `at_client`, no atServer, no `.atKeys` parsing involved.

## Wrap flow — sender wraps an AES shared key for a peer

```mermaid
sequenceDiagram
  participant App
  participant atClient as at_client EncryptionService
  participant atChops as at_chops (hybrid)
  participant Native as at_chops_pq_native
  participant Server as atServer

  App->>atClient: encrypt(value) for @bob
  atClient->>Server: lookup:pq_publickey.@bob
  Server-->>atClient: X25519_pk ‖ MLKEM_pk  (or absent)
  alt PQ-capable
    atClient->>atChops: encryptHybrid(AES_key, peerHybridPk)
    atChops->>atChops: gen eph_X25519 keypair
    atChops->>Native: ML-KEM-768.Encaps(MLKEM_pk)
    Native-->>atChops: pq_ct(1088B), pq_ss(32B)
    atChops->>atChops: classical_ss = X25519(eph_sk, peer_X25519_pk)
    atChops->>atChops: prk = HKDF-Extract(salt, classical_ss‖pq_ss)
    atChops->>atChops: wrap_key = HKDF-Expand(prk, info)
    atChops->>atChops: AES-256-GCM.Seal(wrap_key, nonce, aad, AES_key)
    atChops-->>atClient: envelope(ver‖suite‖eph_pk‖pq_ct‖nonce‖ct‖tag)
    atClient->>Server: update shared_key.@bob with enc:0101
  else fallback
    atClient->>atChops: encryptString(AES_key, RSA pk)
    atClient->>Server: update shared_key.@bob with enc:rsa
  end
```

## Unwrap flow — recipient decrypts the wrapped shared key

```mermaid
sequenceDiagram
  participant Server as atServer
  participant atClient
  participant atChops
  participant Native as at_chops_pq_native

  atClient->>Server: lookup shared_key.@me for @alice
  Server-->>atClient: envelope + metadata enc:0101
  atClient->>atChops: decryptHybrid(envelope, selfHybridSk)
  atChops->>atChops: parse ver, suite, eph_pk, pq_ct, nonce, ct, tag
  atChops->>Native: ML-KEM-768.Decaps(MLKEM_sk, pq_ct)
  Native-->>atChops: pq_ss (32B, implicit-rejection on bad ct)
  atChops->>atChops: classical_ss = X25519(self_X25519_sk, eph_pk)
  atChops->>atChops: derive wrap_key (HKDF as in wrap)
  atChops->>atChops: AES-256-GCM.Open(wrap_key, nonce, aad, ct‖tag)
  alt tag valid
    atChops-->>atClient: AES_key
  else tag invalid
    atChops-->>atClient: error (covers KEM failure too)
  end
```

## Negotiation / dispatch

```mermaid
flowchart TD
  A[Need to wrap for peer P] --> B{peer pq_publickey<br/>cached or fetchable?}
  B -- no --> C{seen PQ before?<br/>TOFP record}
  C -- yes --> D[log pq.downgrade.suspected]
  C -- no  --> E[RSA fallback<br/>tag enc:rsa]
  D --> E
  B -- yes --> F{local at_chops<br/>supports suite?}
  F -- no  --> E
  F -- yes --> G["Hybrid wrap<br/>tag enc:ver‖suite"]
```

## `.atKeys` post-upgrade migration

```mermaid
sequenceDiagram
  participant App
  participant Auth as at_auth keyfile
  participant Chops as at_chops
  participant Native as at_chops_pq_native
  participant Server as atServer

  App->>Auth: load .atKeys
  Auth-->>App: keys (pqVersion absent)
  App->>Chops: generateHybridKeypair()
  Chops->>Native: ML-KEM-768.Keypair()
  Native-->>Chops: MLKEM (pk, sk)
  Chops->>Chops: X25519 keypair
  Chops-->>App: HybridKeyPair
  App->>Auth: persist .atKeys (pqVersion=1)
  App->>Server: update:pq_publickey.@self = X25519_pk ‖ MLKEM_pk
```

## Dependency / build graph

```mermaid
flowchart LR
  subgraph DartPkgs
    AC[at_client]
    CH[at_chops]
    PQDart[at_chops_pq_native<br/>Dart wrapper]
    AU[at_auth]
  end
  subgraph FFI
    BIND[ffigen bindings.dart]
    SHIM[oqs_shim.c]
  end
  subgraph Native
    LIBOQS[(mlkem-native<br/>static lib)]
  end
  subgraph PlatformBuilds
    iOS[iOS<br/>CocoaPods]
    Mac[macOS<br/>CocoaPods]
    And[Android<br/>CMake/Gradle]
    Linux[Linux<br/>CMake]
    Win[Windows<br/>CMake]
  end

  AC --> CH
  AU --> CH
  CH --> PQDart
  PQDart --> BIND
  BIND --> SHIM
  SHIM --> LIBOQS
  LIBOQS --> iOS
  LIBOQS --> Mac
  LIBOQS --> And
  LIBOQS --> Linux
  LIBOQS --> Win
```

## Wire envelope byte layout

```mermaid
flowchart LR
  V[ver<br/>1B] --> S[suite<br/>1B] --> E[eph_X25519_pk<br/>32B] --> CT[pq_ct<br/>1088B] --> N[nonce<br/>12B] --> G[gcm ct+tag<br/>48B]
```

Total = 1182 B.
