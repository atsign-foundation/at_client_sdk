# major-v4 — three packages, one dependency chain

This directory holds the plan for the three v4 majors named in
[`docs/projects/wasm/implementation-plan.md`](../projects/wasm/implementation-plan.md)
§10 (the publish ladder). That table is authoritative on scope and ordering — these
docs cite it by task id (`I<n>`, `T<n>`) rather than restating it.

**This index rides on `st/at_client-v4` only** — the last package in the stacking
order below — not duplicated onto `st/at_utils-v4` or `st/at_lookup-v4`. Each of those
two branches carries only its own package doc; `at_utils.md` and `at_lookup.md` here
become visible once the branches are stacked in dependency order.

| Plan | Status | Updated | What it covers |
|---|---|---|---|
| [`at_utils.md`](at_utils.md) | proposed | 2026-09-06 | `at_utils` 4.0.0 — barrel split (I1–I4), the only package that can close a `wasm_gates.yaml` stanza this window |
| [`at_lookup.md`](at_lookup.md) | proposed | 2026-09-06 | `at_lookup` 4.0.0-rc1 — flip `AtConnection`'s socket-typed surface onto `AtTransport` (T1–T5); T6–T8 stay open |
| [`at_client.md`](at_client.md) | proposed | 2026-09-06 | `at_client` 4.0.0-rc1 — connectivity injection, `File` off the public spec, storage backend selectable (I5–I8); no gate this window (D8) |

## Stacking order

Dependency order, not commit order: **`at_utils` → `at_lookup` → `at_client`**. Each
branch currently forks from `trunk` at `124982684` as an empty sibling — before any
*code* commit lands, `st/at_lookup-v4` rebases onto `st/at_utils-v4`'s tip and
`st/at_client-v4` onto `st/at_lookup-v4`'s tip. `resolution: workspace` in the root
`pubspec.yaml` makes this non-optional: a branch carrying `at_utils: ^4.0.0` (or
`at_lookup: ^4.0.0-rc1`) fails `pub get` workspace-wide until the branch it points at
actually publishes that version. The restack is implementation step 0, not part of
these doc commits — until it happens, `at_utils.md` and `at_lookup.md` are each only
reachable from their own branch, and this index (added on `st/at_client-v4`) can't see
them either.

## Shared scope filter

The committed ladder names the phase (`I`, `T`) each package draws from; it does not
by itself decide what rides *this* window. Two cuts apply on top of it, stated once here
so the per-package docs don't repeat them:

- **`at_lookup` is cut to T1–T5.** T6 (route the remaining raw-socket call sites through
  the transport), T7 (a web `SecondaryAddressFinder`) and T8 (publish) stay open — T8
  waits on T6/T7's residual `dart:io` reachability being resolved or explicitly gated.
- **`at_client` is held to I5–I8**, per the storage decision below. I9–I11 (backend-neutral
  sync queue, dropping the direct `hive` dependency, publish) are out of scope.

**D8: `at_client`'s v4 storage debt is I8 only.** The backend becomes selectable from
`AtClientPreference`; `at_persistence_secondary_server` itself staying on the
`AtClientStorage` interface is explicitly deferred, non-breaking, later work. This is the
project owner's call, not a ladder default — the ladder's `I` phase doesn't itself split
I8 from I9–I11.

No `Co-Authored-By` trailer on any commit under this plan.
