# Notification Delivery & Confirmation

`notificationService.send(...)` returns a notification **id**, and its future
completes once the notification has been accepted for delivery — *not* when the
recipient has it. Awaiting `send()` therefore proves nothing about arrival. That
id is the handle for the two confirmation calls, both on `NotificationService`
and both exported from `package:at_client/at_client.dart`.

**Which call answers which question:**

| You need to know…                    | Call             | Returns              |
| ------------------------------------ | ---------------- | -------------------- |
| "Did it arrive?"                     | `getStatus(id)`  | `NotificationResult` |
| "What happened to it, exactly?"      | `fetch(id)`      | `AtNotification`     |
| "What was in it?" (payload recovery) | `fetch(id)`      | `AtNotification`     |

Confirm when a notification carries an **action that must not be silently
lost**. Do not confirm per-sample telemetry — that costs a remote round trip
per sample, and a stale sample is worthless anyway (see Pattern 2 in
[10-architecture-guide.md](10-architecture-guide.md)). If what you actually
need is a *guaranteed answer* rather than a delivery receipt, that is RPC —
see [13-rpc.md](13-rpc.md).

---

## `getStatus(id)` — two states, so poll with a deadline

```dart
Future<NotificationResult> getStatus(String notificationId);
```

`NotificationResult` carries `notificationID`, an optional `atKey`,
`notificationStatusEnum`, and an optional `atClientException`. The enum has
exactly two values:

```dart
enum NotificationStatusEnum { delivered, undelivered }
```

**`undelivered` does not mean "failed".** The client recognises only the
strings `delivered` and `undelivered`; every other status the atServer might
report — including any still-in-flight state — falls through to
`undelivered`. A single `undelivered` reading is therefore never terminal.
Poll until `delivered` or until *your own* deadline expires.

There is a second reason `undelivered` can appear: when the status query
itself fails, `getStatus` still returns `undelivered`, but sets
`atClientException`. Check that field to tell "the server says not yet" from
"I could not ask".

```dart
/// Polls until delivered, or gives up. Returns null on timeout.
Future<NotificationResult?> awaitDelivery(
  AtClient atClient,
  String notificationId, {
  Duration deadline = const Duration(minutes: 2),
  Duration interval = const Duration(seconds: 3),
}) async {
  final giveUpAt = DateTime.now().add(deadline);

  while (DateTime.now().isBefore(giveUpAt)) {
    final result =
        await atClient.notificationService.getStatus(notificationId);

    if (result.notificationStatusEnum == NotificationStatusEnum.delivered) {
      return result;
    }
    if (result.atClientException != null) {
      // The *query* failed — not the delivery. Worth logging, not fatal.
      logger.warning('status query failed: ${result.atClientException}');
    }
    await Future.delayed(interval);
  }
  return null; // still undelivered when we ran out of time
}
```

---

## `fetch(id)` — the finer status, and the payload

```dart
Future<AtNotification> fetch(String notificationId);
```

Use `fetch` when `getStatus` says `undelivered` and you need to know *why*, or
when you need the notification's body back. Three things to get right:

**1. `status` is a `String`, not an enum.** `AtNotification.status` holds the
server enum's `toString()` — the value carries a `NotificationStatus.` prefix,
so comparing it against a bare `'delivered'` silently never matches. Compare
by suffix:

```dart
final n = await atClient.notificationService.fetch(notificationId);

if (n.status.endsWith('delivered')) {
  final payload = jsonDecode(n.value!);       // safe: value is populated
} else if (n.status.endsWith('queued')) {
  // still in flight — keep waiting, inside the expiration window
} else if (n.status.endsWith('errored')) {
  // will not arrive — resend, or surface it to the user
} else if (n.status.endsWith('expired')) {
  // gone from the keystore; see the guard below
}
```

**2. The server's vocabulary is richer than
`NotificationStatusEnum`.** at_persistence_secondary_server defines
`NotificationStatus { delivered, errored, queued, expired }`. This is exactly
why `fetch` can separate "still queued, retry later" from "errored, will never
arrive" when `getStatus` collapses both to `undelivered`.

**3. An expired or unknown id yields a near-empty object.** `fetch` returns an
`AtNotification.empty()` populated with only `id` and `status`; `value`, `key`,
`from` and `to` are empty or null. Never read `.value` without checking status
first.

`fetch` throws `AtClientException` when the atServer is unreachable or times
out, so wrap it where a failed diagnosis must not take down the caller.

> **Not to be confused with** `AtCollection`'s deprecated `fetch()`, which is
> an alias for `get()` — see [03-query-api.md](03-query-api.md).
> `NotificationService.fetch(id)` is current and unrelated.

---

## Expiration bounds the whole exercise

A notification lives only as long as its expiration, after which it leaves the
keystore entirely. `send()` defaults to
`NotificationService.defaultExpiration` — **15 minutes**:

```dart
final id = await atClient.notificationService.send(
  to: '@bob'.toAtsign(),
  namespace: 'jobs.my_app',
  body: jsonEncode(command),
  expiration: const Duration(minutes: 30), // must outlast your poll deadline
);
```

Once it has expired, `fetch` reports `expired` and `getStatus` reports
`undelivered` — **indistinguishable from a delivery that failed**. So the
confirmation deadline has to sit inside the expiration window; a poll that
starts too late cannot tell you anything. When you intend to confirm, set
`expiration` deliberately rather than inheriting the default.

Note that the older `notify(NotificationParams...)` path carries its own,
much longer default, set on `NotificationParams` rather than here. Do not
assume an expiration you read on one path applies to the other.

---

## Both calls are remote

`getStatus` goes through `atClient.notifyStatus` (the `notify:status` verb);
`fetch` executes `notify:fetch` against the remote secondary. Neither has a
local-only mode and neither is served from the local keystore, so **both fail
offline** regardless of `AtClientPreference` — see
[12-remote-atserver.md](12-remote-atserver.md). Budget a round trip per poll,
which is the other reason to keep poll intervals sane rather than tight.
