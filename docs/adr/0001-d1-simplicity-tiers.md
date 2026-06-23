# ADR 0001 — D1 delivers as two tiers (shared `nskey` default, per-client `group` opt-in)

- **Status:** Accepted (2026-06-20)
- **Context doc:** [`docs/crypto-roadmap.md`](../crypto-roadmap.md) →
  "D1 — preserving legacy simplicity (two tiers)" and "Application migration &
  rollout".

## Table of contents

- [Context](#context)
- [Decision](#decision)
- [Consequences](#consequences)
- [Alternatives considered](#alternatives-considered)

## Context

D1's goal is post-quantum-safe messaging while **preserving the legacy
developer experience**: *Alice shares with `@bob`; every bob client with
namespace access, present and future, decrypts it instantly, offline, with no
ceremony.*

The earlier D1 framing made the **per-client group** model (X-Wing leaves,
epoch keys, explicit membership, single-owner lock) the path for *all* self and
shared encryption. That delivers per-device revocation and a route to forward
secrecy, but it is in direct tension with legacy simplicity:

> Instant, offline access for a *future* device fundamentally requires a
> **copyable shared key**. Non-copyable per-device keys force re-encryption to
> each new device (online, not instant). You cannot have both.

Making per-client groups mandatory for D1 therefore taxes every app with
identity/membership machinery it does not need, and regresses the
"future device just works" property that legacy apps rely on — to buy
per-device security most namespaces never ask for.

## Decision

Deliver D1 in **two tiers** over the M0 pluggable `CryptoProvider` seam:

- **D1 Tier1 — `nskey` (default).** A per-`(atSign, namespace)` X-Wing keypair
  replacing the atSign-wide RSA key, `selfEncryptionKey`, and `shared_key.*`.
  **Enrollment-granular and copyable**, distributed at enrollment approval, so
  future clients read instantly/offline with full history — byte-for-byte legacy
  semantics, now PQ-safe and namespace-scoped. **No `SecureGroup`, `KeyPackage`,
  `clientId`, or single-owner lock in the app's face.** Key rotation is
  **opt-in** (post-compromise security at namespace granularity), distributed
  over the self-group secret channel and doubling as the revocation primitive.

- **D1 Tier2 — `group` (opt-in).** The per-client group provider, declared by a
  namespace that needs **per-device** revocation or forward secrecy. It is also
  the **substrate D2/MLS swaps its engine into.**

The already-built per-client secret-sharing substrate is **not discarded**: in
D1 Tier1 it is the per-enrollment rotation/distribution plumbing; in D1 Tier2 it
is the per-client data path. Senders **negotiate per-destination** (provider seam +
`appMetadata.providerId`), downgrading to the recipient's best supported tier,
so mixed-tier and legacy peers interoperate automatically.

This reframes the *delivery* of milestones M2–M4 (per-client group → opt-in
D1 Tier2 + substrate); the milestones themselves and D2 (M5–M6) are unchanged.

## Consequences

**Positive**
- App developers keep the legacy experience: rebuild → PQ-ready + fully
  compatible; flip one readiness flag → PQ-safe, namespace-scoped data;
  negotiated down for un-upgraded peers (see the migration section + capability
  table).
- Closes the cheap legacy weaknesses by default — PQ (X-Wing), namespace
  scoping (crypto mirrors transport), per-namespace blast radius, and a
  rotatable replacement for the never-rotating `selfEncryptionKey`.
- Heavy machinery (per-device leaves, single-owner lock/lease, membership
  commits) is confined to the opt-in D1 Tier2; most apps never touch it.

**Negative / accepted trade-offs**
- D1 Tier1 does **not** provide per-device revocation granularity or forward
  secrecy. Enrollment revocation cuts *future* access for free and opt-in
  rotation gives namespace-granular PCS, but scrubbing access to
  already-pulled data needs re-encryption — that is D1 Tier2 / D2's job.
- Two data-path providers (`nskey`, `group`) plus `legacy` coexist during the
  ecosystem's lifetime, carried on the provider seam (the seam was built for
  exactly this).
- Cold-start (recipient has no namespace key yet) falls back to the
  atSign-level PQ key, briefly namespace-broad-but-server-gated, self-healing on
  first namespace use; high-security namespaces opt into seal-and-hold instead.

## Alternatives considered

- **Per-client groups mandatory for all of D1** (the prior framing) — rejected:
  taxes every app, regresses instant future-client access, over-buys
  per-device security for the common case.
- **Server-stored per-client leaf secrets** (to recover convenience) — rejected
  in the roadmap (Phase 2): makes cloning the default, opens a PQ
  harvest-now-decrypt-later hole, and couples key/data blast radii.
- **Keep one atSign-wide PQ keypair** (simplest) — rejected: leaves the
  crypto-broader-than-transport weakness (a `chess`-only enrollment would hold
  `banking` keys). Per-namespace is the minimum scope that mirrors enrollment
  authorization.
