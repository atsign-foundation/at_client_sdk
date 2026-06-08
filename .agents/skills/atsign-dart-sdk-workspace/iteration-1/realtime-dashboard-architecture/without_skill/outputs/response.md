# Real-Time Dashboard Architecture for Docker Container Stats

## Short Answer

For a real-time dashboard receiving Docker container stats every 2 seconds, **do not use `AtCollection`**. Instead, use a **notification-based approach** with `AtClient.notificationService` combined with a simple key per container (or a flat key per stat type).

---

## Why Not AtCollection?

`AtCollection` (from the `at_collection_package`) is designed for managing sets of structured objects that need to be persisted, enumerated, and shared. It introduces overhead that is counterproductive for high-frequency streaming data:

- Each update involves a full object lifecycle (serialize, put, notify).
- It is optimized for correctness and persistence, not throughput.
- At 2-second intervals across multiple containers, you are dealing with a stream of ephemeral telemetry values — not a growing collection of records.
- `AtCollection` does not give you a clean "latest value" semantic; it stores and retrieves items by ID within a collection, which requires extra lookup logic.

---

## Recommended Architecture

### 1. Use AtKey + AtClient.put() on the sender side

The Docker stats sender (the other atSign) should write each stat update to a well-known key:

```dart
// Sender side — runs every 2 seconds per container
final key = AtKey()
  ..key = 'container.${containerId}.stats'
  ..sharedWith = dashboardAtSign
  ..namespace = 'dockerstats.your_app'
  ..metadata = (Metadata()
    ..ttl = 10000  // 10 second TTL — data is ephemeral
    ..ttr = -1);   // Cache on receiver side until replaced

await atClient.put(key, jsonEncode(statsMap));
```

Using a short TTL ensures stale data does not linger if the sender stops.

Setting `ttr = -1` (time-to-refresh = cached until replaced) means the receiver's local secondary will cache the value and serve it without a network round-trip on every read.

### 2. Subscribe to notifications on the receiver (dashboard) side

```dart
atClient.notificationService
    .subscribe(regex: 'container\\..*\\.stats\\.dockerstats\\.your_app@')
    .listen((notification) {
  final containerId = extractContainerId(notification.key);
  final stats = jsonDecode(notification.value ?? '{}');
  updateDashboard(containerId, stats);
});
```

This gives you push-based updates with no polling. The dashboard reacts the moment a new stat arrives.

### 3. Key naming strategy

Use a consistent, predictable key pattern per container:

```
container.<containerId>.stats.dockerstats.<appNamespace>@<senderAtSign>
```

This lets you:
- Subscribe to all containers with a single regex.
- Subscribe to a specific container by making the regex more specific.
- Read the last known value for any container on demand via `atClient.get(key)`.

---

## Data Flow Summary

```
Docker Host (sender atSign)
  |
  | atClient.put(containerKey, stats) every 2s
  |
  v
atSign Server (sender's secondary)
  |
  | notification pushed to receiver
  |
  v
Dashboard (receiver atSign)
  |
  | notificationService.subscribe().listen(...)
  |
  v
UI update
```

---

## When Would AtCollection Be Appropriate?

Use `AtCollection` when you need to:
- Maintain a list of items (e.g., registered containers, alert history).
- Add/remove items from a shared set.
- Enumerate all items of a type across sessions.

For example, you might use `AtCollection` to store the **registry of known containers**, while using plain `AtKey` + notifications for the **live stats stream**.

---

## Summary

| Concern | Recommendation |
|---|---|
| Live stats updates (2s interval) | `AtClient.put()` + `notificationService.subscribe()` |
| Ephemeral data cleanup | Set `ttl` on the AtKey metadata |
| Receiver-side caching | Set `ttr = -1` |
| Container registry / config | `AtCollection` is appropriate here |
| Key naming | One key per container, regex subscription for all |

The notification-based approach is the idiomatic atPlatform pattern for real-time streaming data and will scale cleanly to many containers without collection management overhead.
