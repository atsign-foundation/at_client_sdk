# pq_chat — Triple Ratchet narrative demo

One file. One command. Watch the entire Triple Ratchet algorithm execute step
by step.

```sh
dart run bin/demo.dart
```

The script runs both parties (`alice` initiator, `bob` responder) in-process.
It prints every key, every state transition, every ratchet step — `BEFORE`,
operation trace, `AFTER` with changed fields highlighted.

## What the demo shows

| Stage | What you observe |
|---|---|
| **Setup** | Identity keys (X25519 + Ed25519 + ML-KEM-768 SPK) and the signed pre-key bundle for each party |
| **SPK signature verify** | Alice validates Bob's Ed25519 signature over his X25519 SPK |
| **PQXDH handshake** | 3 × X25519 DH + 1 × ML-KEM Encaps → initial `rootKey`; first DH ratchet step |
| **Send / receive** | Symmetric chain step (HMAC) → AES-256-GCM seal/open |
| **DH ratchet** | Triggered on receipt of a new peer `dhPk`; mixes DH output into `rootKey` and re-derives the chain keys |
| **KEM ratchet** | Triggered every N sent messages (N=3 in demo, 10+ in production); mixes a fresh ML-KEM `kem_ss` into `rootKey` and rotates the local KEM keypair |

See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) for the full algorithm walkthrough.

## Files

```
3_pq_chat/
├── bin/demo.dart           ← the whole thing
├── docs/ARCHITECTURE.md    ← detailed walkthrough
├── README.md               ← this file
└── pubspec.yaml
```

No `lib/`, no persistence, no two-terminal chat. Deliberate.

## Tunables (in `bin/demo.dart`)

| Constant | Demo value | Production value |
|---|---|---|
| `kemRatchetEvery` | 3 | 10 or higher |

The KEM ratchet interval is lowered so the demo can demonstrate the trigger
within a short scripted run.

## Dependencies

- `pqcrypto: ^0.1.0` — ML-KEM-768 (Kyber)
- `cryptography: ^2.7.0` — X25519, Ed25519, HKDF-SHA256, HMAC-SHA256, AES-256-GCM
