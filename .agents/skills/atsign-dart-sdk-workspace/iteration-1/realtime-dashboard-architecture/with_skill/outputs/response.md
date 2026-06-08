# Architecture Recommendation: Real-Time Docker Stats Dashboard

## Short Answer

**Do not use `AtCollection<T>` for this use case.** Use the **Notifications + SQLite** pattern instead.

---

## Why Not AtCollection?

`AtCollection<T>` is designed for **discrete, addressable records** — items that have independent identity, can be fetched by id, updated, deleted, and shared with specific people. Docker container stats arriving every 2 seconds are the opposite of that:

| Criterion | Your Use Case | AtCollection verdict |
|-----------|---------------|----------------------|
| Data shape | Per-second telemetry samples | Telemetry is not a discrete addressable record |
| Volume | ~30 samples/minute per container, potentially many containers | Medium-high volume; collections are optimized for hundreds to thousands of items, not high-frequency streams |
| Query pattern | Time-window aggregates (AVG CPU, charting over last N minutes) | `Query<T>` does on-device filtering/sorting of discrete records, not time-series aggregation |
| Persistence | Stale samples are worthless | `AtCollection` syncs items to atServer and across devices — not what you want for ephemeral telemetry |
| Sync requirement | No — you want live data, not historical consistency | `AtCollection` with `SyncService` adds sync overhead that is wasteful for discard-after-use samples |

---

## What to Use: Notifications + SQLite

This is the canonical pattern in the SDK for exactly your use case. The dockerstats example (`packages/at_client_flutter/examples/dockerstats/`) demonstrates it end-to-end.

### Publisher Side (the atSign sending Docker stats)

```dart
// Send one notification per sample — no identity, no persistence needed
await atClient.notificationService.send(
  to: recipientAtsign,           // your dashboard's atSign
  namespace: 'sample.nginx.myhost.dockerstats.demos',
  body: jsonEncode(sample.toJson()),
  expiration: const Duration(minutes: 5),  // short TTL — stale stats are useless
);
```

Key points:
- One `send()` call per stats snapshot, every 2 seconds
- Use a short `expiration` (5 minutes is reasonable) — if the dashboard is offline, stale stats should be silently dropped rather than queued up
- The `namespace` becomes the key you subscribe to via regex on the receiver side

### Subscriber Side (your dashboard)

```dart
// 1. Subscribe to the notification stream
atClient.notificationService
    .subscribe(
      regex: r'sample\..*\.dockerstats\.demos',
      shouldDecrypt: true,  // required — publisher encrypts by default
    )
    .listen((notification) async {
      final sample = StatSample.fromJson(jsonDecode(notification.value!));
      // 2. Append to local SQLite — your local accumulation store
      await db.insert('samples', {
        'container': sample.container,
        'cpu':       sample.cpu,
        'mem':       sample.mem,
        'ts':        sample.timestamp.millisecondsSinceEpoch,
      });
    });

// 3. Query SQLite for dashboard display — aggregate runs locally
final rows = await db.rawQuery(
  'SELECT container, AVG(cpu) AS avg_cpu, MAX(mem) AS peak_mem '
  'FROM samples '
  'WHERE ts > ? '
  'GROUP BY container',
  [DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch],
);
```

Key points:
- `shouldDecrypt: true` is **required** — `notificationService.send()` encrypts by default, so the subscriber must decrypt
- The local SQLite database accumulates samples and supports the time-window aggregate queries your dashboard needs
- The notification pipeline is fire-and-forget: missing one sample is acceptable for a live stats view

---

## Domain Object for the Stats Sample

```dart
class StatSample {
  final String container;
  final double cpu;       // percent
  final double mem;       // MB
  final DateTime timestamp;

  StatSample({
    required this.container,
    required this.cpu,
    required this.mem,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'container': container,
    'cpu':       cpu,
    'mem':       mem,
    'ts':        timestamp.toIso8601String(),
  };

  factory StatSample.fromJson(Map<String, dynamic> j) => StatSample(
    container: j['container'] as String,
    cpu:       (j['cpu'] as num).toDouble(),
    mem:       (j['mem'] as num).toDouble(),
    timestamp: DateTime.parse(j['ts'] as String),
  );
}
```

No `typeTag` or `AtCollection.registerFactory` needed — this type is only used in notification bodies, serialized/deserialized manually with `jsonEncode`/`jsonDecode`.

---

## Optional Hybrid: Combine Both Patterns

If your dashboard also needs persistent, user-editable configuration (e.g., alert thresholds, which containers to watch), you can layer `AtCollection<T>` on top for just that config data:

```dart
// AtCollection for persistent alert rules — synced across devices
final rules = await atClient.collection<AlertRule>(
  'rules.dockerstats_app',
  const Duration(days: 365),
  fromJson: AlertRule.fromJson,
  typeTag: 'AlertRule',
);

// Notifications + SQLite for the live metric stream
atClient.notificationService
    .subscribe(regex: r'sample\..*\.dockerstats\.demos', shouldDecrypt: true)
    .listen((notification) async {
      final sample = StatSample.fromJson(jsonDecode(notification.value!));
      await db.insert('samples', sample.toMap());

      // Evaluate incoming sample against user-configured rules
      final activeRules = await rules.query()
          .where((r) => r.obj.appliesToContainer(sample.container))
          .get();

      for (final rule in activeRules) {
        if (sample.cpu > rule.obj.cpuThreshold) {
          triggerAlert(rule.obj.label, sample);
        }
      }
    });
```

The two patterns are fully composable: `AtCollection<AlertRule>` handles the addressable, synced config; notifications + SQLite handles the high-frequency stream.

---

## Decision Summary

```
Is each data record independently addressable and retrievable?
└─ NO (stream of 2-second samples) → Notifications + SQLite

Does the data need to survive the publisher going offline?
└─ NO (stale stats are useless) → Notifications (fire-and-forget; short TTL)

Is the primary query pattern time-window aggregates (AVG, SUM, GROUP BY)?
└─ YES → Notifications + SQLite

Volume > ~10 writes/second sustained? (multiple containers * 0.5/sec each)
└─ POTENTIALLY YES → Notifications + SQLite
```

**Verdict: Notifications + SQLite.** `AtCollection<T>` is not the right tool here — it adds sync overhead, persistence, and an addressable-record model that your use case does not need.

---

## Packages Needed

```yaml
dependencies:
  at_client: ^3.12.0        # core SDK + notification service
  sqflite: ^2.3.0           # local SQLite for sample accumulation
  path: ^1.9.0              # SQLite file path helper
```

For a Flutter dashboard, also add `at_client_flutter: ^1.1.2` for the auth flow.

---

## Reference

- Canonical dockerstats example: `packages/at_client_flutter/examples/dockerstats/`
- Publisher: `packages/at_client/example/bin/dockerstats_publish.dart`
- Architecture decision guide: `references/10-architecture-guide.md`
