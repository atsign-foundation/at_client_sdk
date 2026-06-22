# Server-Assisted Ratchet Design

## Problem

Triple Ratchet on atPlatform is not directly implementable: per-turn keys must be in sync across all of a user's devices, and there is no trusted coordination point.

## Construction

```
Server generates:  S_n  (ML-KEM or X25519 ratchet step, advanced each epoch)
Client holds:      C    (group secret — never leaves clients)
Per-turn key:      K_n = KDF(S_n, C)
```

- Server advances `S_n` each epoch and stores only the current value.
- `C` is derived from an MLS group secret or equivalent — clients derive and rotate it independently.
- The server never has `C`. A client never has raw `S_n` without mixing it with `C`.

## Security Properties

| Property | Achieved | Notes |
|---|---|---|
| Key freshness per message | ✅ | `S_n` fresh each epoch → `K_n` unique per turn |
| Post-compromise security (PCS) | ✅ | Requires rotating both `C` and advancing `S_n` simultaneously |
| Multi-device sync | ✅ | Server is canonical ratchet state; all devices query `S_n` |
| Zero-trust server | ✅ | Server alone cannot decrypt; needs `C` |
| Out-of-order delivery | ✅ | Server can buffer `S_k` by index; clients request by epoch |
| Forward secrecy | ⚠️ | Policy-dependent: server must delete old `S_n` values |

## PCS: 2-of-2 Threshold

After a client compromise, the attacker holds a stale `C`. Recovery:

1. Any active client rotates `C` → old `C` is invalid.
2. Server advances `S_n` → new epoch begins.

Attacker must hold a valid `C` **and** `S_n` for the **same epoch** simultaneously. This is a meaningful 2-of-2 threshold on the decryption path — stronger than pure client-side (where compromise exposes full history) and stronger than MLS in practice (MLS PCS requires an Update proposal from an online device; a compromised offline device blocks healing).

## Gap vs. True Triple Ratchet

**Unauthenticated ratchet advancement.** In Signal's Double Ratchet, the DH exchange between sender and receiver cryptographically guarantees freshness — neither party can replay. Here, clients cannot verify that `S_n` is fresh vs. a replayed or biased server value.

**Mitigation:** Server publishes a hash commitment to the next `S_n` before revealing the current one. Clients verify the chain. This closes most of the gap without requiring trust.

## Comparison to MLS

| | MLS | Server-Assisted Ratchet |
|---|---|---|
| PCS trigger | Update proposal (device must be online) | C rotation (any active client) + S_n advance (automatic) |
| Multi-device | TreeKEM (complex) | Server as canonical state (simple) |
| Server role | Passive delivery | Active ratchet participant |
| Audited construction | ✅ RFC 9420 | ❌ Novel |
| Zero-trust | ✅ | ✅ |

## Open Questions

1. **Commitment scheme** — exact construction for server's hash-chain commitment to `S_n`.
2. **C rotation protocol** — how clients agree on and distribute a new group secret without a trusted coordinator.
3. **ML-KEM ratchet step** — concrete construction for `S_n` (pure X25519, pure ML-KEM, or hybrid).
4. **Epoch boundaries** — what triggers `S_n` advancement: per-message, per-time-window, or client-driven?
