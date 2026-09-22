# pb3-stage1.md — unblocking Mode E construction in `at_client`

**Status:** implemented — `st/wasm/stage1` (off `st/at_lookup-v4`), [PR #2257](https://github.com/atsign-foundation/at_client_sdk/pull/2257), 2026-09-22.
**Purpose:** close the construction-time gap D-17/D-18 flagged as still open — a client
built on a non-Hive `AtClientStorage` bundle with `preference.isLocalStoreRequired: false`
could not be constructed at all, and where it could (no storage injected), chops/crypto
setup was silently skipped rather than degrading gracefully.
**Lane:** this is `at_client`-side plumbing only. It does not ship `RemoteOnlyAtClientStorage`
— see [Scope](#scope) — and it does not touch transport, sync-queue, or key-storage design.
For the ruling this closes see [`decisions.md`](decisions.md) D-18 item 2 ("the gateway
must admit a remote-only bundle"); for the acceptance gates it's a precondition for see
[`acceptance.md`](acceptance.md) §9a.2, gates X-R1/X-R2; for the storage-bundle interface
itself see [`design.md`](design.md#22-storage-bootstrap) §2.2.

## The gap

D-18 named this exactly, from the storage-bundle side (`decisions.md`, "the gateway must
admit a remote-only bundle", item 2):

> The `isLocalStoreRequired` guard must not reach the bundle path. `at_client_impl.dart:824`
> currently throws when a keystore is injected while `preference.isLocalStoreRequired` is
> false — exactly backwards for this design.

Two call sites carried that backwardness:

- `at_client_factory.dart:71-77` refused **any** injected storage when the flag was false —
  not just Hive, which is the only backend the flag actually protects (a Hive box on disk
  with nothing configured to read it back).
- `at_client_impl.dart`'s `_init` gated **all** of chops/crypto setup, plus the expiry/
  availability timers, behind that same flag. A no-storage config (flag false, nothing
  injected) skipped chops entirely instead of falling back to its existing no-key-material
  path — so `atChops` came back `null` even in configs several existing tests already
  exercised.

## What changed

**`at_client_factory.dart`** — narrowed the guard to the backend it's actually protecting:

```dart
if (storage is HiveAtClientStorage && !preference.isLocalStoreRequired) {
  throw ArgumentError.value(storage, 'storage', ...);
}
```

A non-Hive bundle (a fake today, `RemoteOnlyAtClientStorage` once it exists) now
constructs under `isLocalStoreRequired: false`.

**`at_client_impl.dart`'s `_init`** — split one `if (isLocalStoreRequired)` into three
independently-gated blocks:

| Block | Gate | Why |
| --- | --- | --- |
| Storage / `localSecondary` | `injected storage != null \|\| isLocalStoreRequired` | unchanged behavior, just widened to admit the injected case |
| Chops / crypto | unconditional | D-18's point: whether the bundle is durable is the bundle's business, not a reason to skip key material entirely |
| Expiry / availability timers | `isLocalStoreRequired` only | a write-through remote store rearming on TTL is a separate design question, out of scope here (see [Scope](#scope)) |

`_createAtChops`'s no-`atKeysIo` branch read `localSecondary!.get...Key` with non-null
assertions; once chops runs unconditionally, a genuinely-empty config (`localSecondary ==
null`) hits those reads. Changed to `localSecondary?.` so that config degrades to the
existing no-key-material fallback (an `AtChopsImpl` built from null keypairs, already
logged as such) instead of throwing an NPE.

## Scope

This ships the *precondition* for D-17/D-18's remote-only lane, not the lane itself.
`RemoteOnlyAtClientStorage` — the concrete write-through bundle `implementation-plan.md`
names as "implied and not yet written up" — does not exist in this repo. Stage1 only makes
the factory/`_init` seam accept *any* non-Hive `AtClientStorage`; tests here use a fake
(`InMemoryAtClientStorage`) in its place. X-R1 (constructs with no Hive/SQLite in-process)
and X-R2 (reads data written by a local-storage client) stay open until that bundle lands.

Also explicitly out of stage1, filed as follow-ups rather than silently dropped:

- **Barrel split** — `at_client.dart` exports both Hive and `at_lookup_io.dart`'s
  `secureSocketLookUps`; a Hive-only split doesn't make the barrel wasm-safe alone, so it's
  one follow-up covering both, not part of this slice.
- **`withSecureSocket` caller sweep** — verification-only, a PR-description checklist item,
  not a code change.
- Timer rearming under a write-through remote store (mentioned above) — a separate design
  question.

## Tests

`packages/at_client/test/at_client_mode_e_construction_test.dart` (new, 4 cases) plus
targeted additions to `at_client_create_test.dart`, `no_commit_test.dart`,
`put_request_test.dart`. Full Hive-path regression
(`create_at_chops_logging_test.dart`, `side_by_side_storage_test.dart`,
`at_client_impl_test.dart`) unaffected. Detail: [`plans/wasm/spike/pb3-stage1-plan.md`](../../../plans/wasm/spike/pb3-stage1-plan.md)
(git-ignored, local planning copy — this doc is the committed record).

## Open question, not resolved here

D-17's amendment and D-18 both describe this gap as still open as of their last edit.
Whether to update those entries to point at this doc (vs. leaving their dated history
untouched and letting this file be the forward reference) is a call for whoever owns
`decisions.md` — not made unilaterally in this pass.
