# decisions.md, the at_chops 4.0.0 migration ledger

One ruling per section. A ruling that changes is corrected in place and its
status says so.

| Status | Means                 |
| ------ | --------------------- |
| `LIVE` | Stands as ruled.      |

## D1. at_lookup drops the deprecated atChops credential ladder

`LIVE`. The injected `AtAuthenticator` becomes the only authentication path;
at_lookup no longer carries a fallback through `AtChops`. at_lookup moves to
4.0.0-rc.1 alongside the drop.

Why: at_chops 4.0.0 removes the stateful `AtChops` facade the ladder called
through, so the fallback has nothing left to call once at_lookup takes the
new at_chops major.

## D2. at_client keeps `AtChops` as a deprecated, inert shim; the package stays on 3.x

`LIVE`. `AtChops` becomes an at_client-owned, deprecated, final class with a
private constructor and no members, so `null` is the only value a caller can
pass. Every deprecated `atChops` parameter, getter and setter keeps its
existing signature; the getter returns `null`. No code in at_client builds an
algorithm implementation through a facade — everything calls the stateless
at_chops 4 algorithms directly. The shim is removed in at_client 4.0.0;
at_client itself continues on its 3.x line through this migration, and
at_auth continues its own 4.0.0 rc track independently.

Why: at_client's public API carries `atChops` on several constructors and
accessors that external callers still pass or read. Deleting the parameter
outright breaks every one of them on a dependency bump alone; making it an
inert, always-null shim keeps the signature stable while nothing internal
depends on the type doing anything.

## D3. One integration branch, one PR per slice, then the integration PR into trunk

`LIVE`. `xl/feat/at-chops-4` is the integration branch. Each slice
(at_lookup, at_auth, at_client, the remaining consumers) opens its own PR
into it; this PR — the workspace rejoin and this document — is the
integration PR from `xl/feat/at-chops-4` into trunk, and stays open until the
last slice merges.

Why: a pub workspace resolves one version of `at_chops` for every member, so
trunk cannot hold a workspace with some members migrated to 4.0.0-rc.1 and
others still on 3.x. Landing each slice on an integration branch keeps the
half-migrated state off trunk until every slice is in.
