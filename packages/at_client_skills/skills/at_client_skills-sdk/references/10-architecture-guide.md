<!-- verified: at_client ^3.12.0 — update on next minor release -->

# Architecture Decision Guide

## AtCollection\<T> vs Notifications + SQLite

This guide helps you pick the right data architecture **before writing code**.
Both patterns are valid and complementary — a single app can use both at once.

---

## Decision Table

| Criterion            | Use `AtCollection<T>`                            | Use Notifications + SQLite                   |
| -------------------- | ------------------------------------------------ | -------------------------------------------- |
| **Data shape**       | Discrete typed records                           | High-frequency telemetry / event streams     |
| **Persistence**      | Synced to atServer; available across devices     | Local only; accumulated from notifications   |
| **Sharing model**    | Per-item, shared with named atSigns              | One publisher → many subscribers             |
| **Query needs**      | Rich queries, reactive watches, sub-collections  | Time-window aggregates, GROUP BY, charting   |
| **Volume**           | Low–medium (hundreds to thousands of items)      | High (per-second metrics, logs, traces)      |
| **Sync requirement** | Yes — SyncService keeps devices consistent       | No — notifications are fire-and-forget       |
| **Primary examples** | Todos, contacts, notes, documents, chat messages | Docker stats dashboard, analytics, telemetry |

---

## Pattern 1: AtCollection\<T>

Best for **discrete, addressable records** that need to be created, updated,
deleted, and shared with specific people.

```dart
// Publisher: create a todo and share it with @bob
final todos = await atClient.collection<Todo>(
  'todos.my_app',
  const Duration(days: 365),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);

await todos.create(
  obj: Todo(title: 'Buy groceries'),
  sharedWith: {'@bob'.toAtsign()},
);

// Receiver (@bob): reactive watch
StreamBuilder<List<CItem<Todo>>>(
  stream: todos.query().where((t) => !t.obj.done).watch(),
  builder: (ctx, snap) { ... },
)
```

**Choose this when:**

- Records have identity (can be retrieved, updated, or deleted by id)
- Data must persist when the publisher is offline
- Sharing is per-item and addressable (specific recipients)
- You need `Query<T>` features: filtering, sorting, pagination, sub-collections

---

## Pattern 2: Notifications + SQLite (the Dockerstats Pattern)

Best for **high-frequency streaming data** where individual samples have no
persistent identity and the value comes from aggregate views across many
samples.

### Publisher side

```dart
// Send one notification per sample — no identity, no persistence
await atClient.notificationService.send(
  to: recipientAtsign,
  namespace: 'sample.nginx.myhost.dockerstats.demos',
  body: jsonEncode(sample.toJson()),
  expiration: const Duration(minutes: 5),  // short TTL — stale samples are useless
);
```

### Subscriber side

```dart
// Subscribe to a namespace regex.
// shouldDecrypt: true is needed because the publisher encrypts by default
// (shouldEncrypt defaults to true on the send() side).
atClient.notificationService
    .subscribe(regex: r'sample\..*\.dockerstats\.demos', shouldDecrypt: true)
    .listen((notification) async {
      final sample = StatSample.fromJson(jsonDecode(notification.value));
      await db.insert('samples', sample.toMap());  // append to local SQLite
    });

// Query for dashboard — aggregate runs on the local DB
final rows = await db.rawQuery(
  'SELECT container, AVG(cpu) as avg_cpu '
  'FROM samples WHERE ts > ? '
  'GROUP BY container',
  [cutoff.millisecondsSinceEpoch],
);
```

**Choose this when:**

- Data is time-series: each sample is meaningful only in context of others
- Volume is high (multiple samples per second)
- Recipients accumulate their own local view (not shared with others)
- Aggregate queries (sum, average, time-windows) drive the UI
- Missing a sample is acceptable (fire-and-forget)

---

## Canonical Example

The dockerstats example in the SDK demonstrates the full Notifications +
SQLite pattern:

- **Publisher**: `packages/at_client/example/bin/dockerstats_publish.dart`  
  Uses `atClient.notificationService.send()` in a polling loop.  
  Short `expiration` (5 min) — stale samples are silently dropped.

- **Flutter subscriber**: `packages/at_client_flutter/examples/dockerstats/`  
  Receives notifications, appends to SQLite, renders charts.

---

## Hybrid: Both in One App

The two patterns coexist naturally. For example, a monitoring dashboard
might use:

- `AtCollection<AlertRule>` for user-configured alert thresholds  
  (discrete, shared, editable, synced across devices)

- Notifications + SQLite for the live metrics stream  
  (high-frequency, local, aggregated for charting)

```dart
// Collection: alert rules synced and shared
final rules = await atClient.collection<AlertRule>('rules.monitor_app', ttl);

// Notifications: live metric stream → local SQLite
atClient.notificationService
    .subscribe(regex: r'metric\..*\.monitor_app', shouldDecrypt: true)
    .listen((n) async {
      final metric = Metric.fromJson(jsonDecode(n.value));
      await db.insert('metrics', metric.toMap());

      // Check against the synced rules
      final matchingRules = await rules.query()
          .where((r) => r.obj.appliesToMetric(metric))
          .get();
      for (final rule in matchingRules) {
        if (metric.value > rule.obj.threshold) triggerAlert(rule, metric);
      }
    });
```

---

## Quick Decision Checklist

```text
Is each data record addressable and independently retrievable?
├─ YES → AtCollection<T>
└─ NO (stream of samples) → Notifications + SQLite

Does the data need to survive the publisher going offline?
├─ YES → AtCollection<T> (synced to atServer)
└─ NO → Notifications (fire-and-forget; stale samples discarded)

Is the primary query pattern a time-window aggregate (AVG, SUM, GROUP BY)?
├─ YES → Notifications + SQLite
└─ NO → AtCollection<T> + Query<T>

Is volume > ~10 writes/second sustained?
├─ YES → Notifications + SQLite
└─ NO → AtCollection<T>

Do you need both persistent records AND a live metric stream?
└─ Both patterns in the same app
```
