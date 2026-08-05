# Remote vs Local atServer Operations

Where a `put` / `get` / `delete` runs is governed by
`AtClientPreference.remoteLocalPref` (default `RemoteLocalPref.localOnly`):
operations go to the **local** secondary (the on-device keystore) and the
change reaches the cloud atServer later, in the background, via `SyncService`
(see [11-sync.md](11-sync.md)). That is the right default for almost all app
code: reads are instant and offline-tolerant, writes survive a dropped
connection.

Two built-in exceptions are always remote, regardless of any preference or
option: reading another atsign's key that you don't hold a `cached:` copy of
(a `lookup`/`plookup` against the owner's atServer), and everything on the
notification path (`notify` and friends).

When you need server-side truth beyond that — read-your-write consistency,
delivery-critical writes, reading data that hasn't synced yet — `at_client`
gives you two levers:

- **Per operation** — the request-options objects below.
- **Client-wide** — `remoteLocalPref = RemoteLocalPref.remoteOnly`, which
  routes every `get`/`put`/`delete` on that client to the remote atServer.

---

## `PutRequestOptions.useRemoteAtServer`

Write straight to the cloud secondary instead of the local one:

```dart
await atClient.put(
  key,
  value,
  putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
);
```

Use when a write must be on the server _now_ and you cannot wait for the next
sync round — e.g. a coordination key another process polls, or a mutex/lock key
(`Metadata()..immutable = true` written remotely so the first writer wins across
instances — see [14-multi-agent.md](14-multi-agent.md)). For ordinary app data,
prefer the default local write + background sync.

## `GetRequestOptions.useRemoteAtServer` / `bypassCache`

```dart
// Read directly from the cloud secondary (skip the local keystore)
final v = await atClient.get(
  key,
  getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
);

// Skip this atsign's cache of another atsign's data (force a fresh remote read
// of a cached: shared key)
final fresh = await atClient.get(
  key,
  getRequestOptions: GetRequestOptions()..bypassCache = true,
);
```

- **`useRemoteAtServer`** — read from the cloud secondary rather than the local
  synced copy. Use right after a remote write, or when the local cache may be
  stale and you need the authoritative value.
- **`bypassCache`** — when reading another atsign's key (non-`cached:` shape —
  already a remote lookup by definition), tell the server chain to skip its
  cached copy and fetch fresh from the owner's atServer.

The two are independent: `useRemoteAtServer` chooses _which secondary_ answers
for keys that resolve locally; `bypassCache` chooses _whether a remote lookup
may be served from cache_.

## `DeleteRequestOptions.useRemoteAtServer`

```dart
await atClient.delete(
  key,
  deleteRequestOptions: DeleteRequestOptions()..useRemoteAtServer = true,
);
```

Same idea for deletes — remove the key on the cloud secondary immediately
rather than deleting locally and syncing the tombstone later.

## `keyExists`

```dart
final onServer = await atClient.keyExists(key, /* useRemoteAtServer */ true);
```

Check existence against the remote atServer (`true`) or the local keystore
(`false`; `null` follows the client's `remoteLocalPref`).

## Client-wide: `AtClientPreference.remoteLocalPref`

```dart
final prefs = AtClientPreference()
  ..remoteLocalPref = RemoteLocalPref.remoteOnly  // default: localOnly
  /* ...the rest of your preference setup... */;
```

With `remoteOnly`, every `get`/`put`/`delete` on the client runs against the
remote atServer and local storage is not written (a syncing client still pulls
the changes down afterwards). Because `AtCollection<T>` operations are plain
`put`/`get`/`delete` under the hood, this preference is also how you make
**collection** operations remote — there is no per-call option at the
collection layer. Typical use: a stateless agent instance that pairs
`remoteOnly` with a no-op sync service
(see [14-multi-agent.md](14-multi-agent.md)).

One subtlety: passing a request-options object overrides the preference with
that object's `useRemoteAtServer` value — which defaults to `false`. So on a
`remoteOnly` client, supply options only when you actually set the flag.

---

## When to reach for remote operations

| Situation                                             | Use                                                                                  |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Ordinary app data (todos, notes, shares)              | **Default** — local write, background sync                                           |
| Cross-process coordination / mutex keys               | `put` + `useRemoteAtServer = true`                                                   |
| Read-your-write right after a remote write            | `get` + `useRemoteAtServer = true`                                                   |
| Cached copy of another atsign's key looks stale       | `get` + `bypassCache = true`                                                         |
| Stateless / horizontally-scaled instance with no sync | `remoteLocalPref = remoteOnly` client-wide (see [14-multi-agent.md](14-multi-agent.md)) |

> Remote operations trade offline-tolerance and speed for immediacy. They open
> a network round-trip on every call and fail when the atServer is unreachable —
> so scope them to the few operations that genuinely need server-side truth, and
> leave the rest on the default synced path.

## AtCollection-first boundary

`AtCollection<T>` methods take no per-operation request-options parameters —
collection operations follow whatever the *client* is configured to do:

- Default (`remoteLocalPref = localOnly`): every collection op is local +
  background sync — right for app data.
- `remoteLocalPref = remoteOnly`: every collection op (like everything else on
  that client) runs against the remote atServer.

What you cannot do is flip a *single* collection call to remote. For the few
keys that genuinely need per-operation control — cross-process coordination
keys, mutex/lock keys, read-your-write probes — drop below `AtCollection` to
raw `put`/`get` with request options. These are *infrastructure*, not app
data — give them a distinct key-name prefix within your app's namespace (e.g.
`lock.` or `session_mutexes.`, as `AtRpc` does within its `__rpcs` namespace)
so they never collide with collection keys, and keep everything else in
collections.
