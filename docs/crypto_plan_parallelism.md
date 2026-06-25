# Wave-1 / Wave-2 parallelism: can wave 2 start before wave 1 finishes?

Scope: the D1 delivery plan in
[section 7 — Delivery plan & work packages](crypto_impl_plan.md#7-delivery-plan--work-packages).

## Table of contents

- [Answer](#answer)
- [Per wave-2 item](#per-wave-2-item)
  - [WP-SS — secret-sharing substrate (#2008)](#wp-ss--secret-sharing-substrate-2008)
  - [WP10 — enrollment-conveyance key (#2009)](#wp10--enrollment-conveyance-key-2009)
- [The nuance on WP1](#the-nuance-on-wp1)
- [Summary](#summary)
- [Caveat](#caveat)

## Answer

**Yes — both wave-2 items can overlap wave 1. The only wave-1 work that
genuinely gates them is WP1 (at_chops 3.3.0 / `pqSeal`), not WP2 / WP3 / WP4.**

The "waves" in the plan are parallelism groupings, not barriers — the actual
gating is the per-WP dependency list. The plan says so directly: land the
interface PRs (WP1 / WP2 / WP3 signatures, "stubs OK") first so every track
compiles against stable shapes and "never blocks on another."

## Per wave-2 item

### WP-SS — secret-sharing substrate (#2008)

- Only stated prerequisite is *"on at_chops 3.3.0"* — i.e. **WP1**, because the
  `__ssenv` envelopes seal via `pqSeal`.
- **No dependency on WP2, WP3, or WP4.** The critical-path line lists
  `WP1 + WP3 + WP-SS + WP10` as *siblings* feeding WP6, which confirms WP-SS
  does not wait on WP3 either.
- Can start the moment `pqSeal` is stable on trunk, while WP2 / WP3 / WP4 are
  still in flight.

### WP10 — enrollment-conveyance key (#2009)

- Track B, "land before WP6." **No stated dependency on WP2 / WP3 / WP4.**
- The KEM primitives (X-Wing) are already in the **baseline** (at_chops 3.2.1),
  so the keypair work can begin immediately.
- If its conveyance seals via `pqSeal` it wants WP1 for that part, but nothing
  in wave 1 blocks it from starting.

## The nuance on WP1

`pqSeal` / `pqOpen` is itself already in flight as the **wave-0 PR #1993**. So
development of WP-SS / WP10 can build against that primitive even before WP1's
stateless-core repackaging finishes. You only need at_chops **3.3.0 published**
before WP-SS is *releasable* — not before it is *started*.

## Summary

The wave-1 → wave-2 boundary is **soft**: WP1 / `pqSeal` is the real gate;
**WP2, WP3, and WP4 do not block wave 2 at all.**

| Wave-1 WP | Blocks wave 2? |
|-----------|----------------|
| WP1 (at_chops 3.3.0 / `pqSeal`) | Yes — the one real gate (and already arriving via wave-0 #1993) |
| WP2 (`WritableAtKeys` + `AtKeysIo`) | No |
| WP3 (`CryptoContext.keys`) | No — sibling of WP-SS on the critical path, not a prerequisite |
| WP4 (`LocalKeystoreAtKeysIo`) | No |

## Caveat

This is read off the plan's stated dependencies. To confirm it against reality,
sanity-check what the `gkc-pqmls-spike` substrate code actually imports — in
particular whether the prototype `__ssenv` path already touches `CryptoContext`
(WP3), since the spike is where WP-SS is being carved from.
