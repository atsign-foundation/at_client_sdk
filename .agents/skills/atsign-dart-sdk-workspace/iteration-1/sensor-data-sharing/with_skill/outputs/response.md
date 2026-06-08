# Sharing Sensor Readings with @device2: AtCollection vs Notifications

For sensor readings sent every few seconds, **use the Notifications + SQLite pattern** — not `AtCollection<T>`.

## Why Not AtCollection for This Use Case

`AtCollection<T>` is designed for discrete, addressable records — things like todos, notes, contacts, and documents. It shines when:

- Each record has identity (can be retrieved, updated, or deleted by id)
- Data must persist when the publisher is offline
- Volume is low to medium (hundreds to thousands of items)

Sensor readings arriving every few seconds are **high-frequency telemetry**. Storing each reading as a collection item would:

- Rapidly accumulate items with no meaningful identity
- Overwhelm the atServer sync mechanism (not designed for sustained >~10 writes/second)
- Create a collection of stale data points that are only useful in aggregate

## The Right Pattern: Notifications + SQLite

Send each sensor reading as a notification with a short TTL. The receiver subscribes, appends incoming samples to a local SQLite database, and queries that database for aggregated views.

### Publisher Side (your sensor device)

```dart
import 'dart:convert';
import 'package:at_client/at_client.dart';

Future<void> sendReading(AtClient atClient, SensorReading reading) async {
  await atClient.notificationService.send(
    to: '@device2'.toAtsign(),
    namespace: 'reading.sensor.my_app',
    body: jsonEncode(reading.toJson()),
    expiration: const Duration(minutes: 5), // stale samples are useless
  );
}

// Call on a timer
Timer.periodic(const Duration(seconds: 2), (_) async {
  final reading = await sensorHardware.readLatest();
  await sendReading(atClient, reading);
});
```

### Subscriber Side (@device2)

```dart
import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:sqflite/sqflite.dart'; // or drift, sqlite3, etc.

void startSubscription(AtClient atClient, Database db) {
  // shouldDecrypt: true because the publisher encrypts by default
  atClient.notificationService
      .subscribe(regex: r'reading\.sensor\.my_app', shouldDecrypt: true)
      .listen((notification) async {
        final reading = SensorReading.fromJson(jsonDecode(notification.value!));
        await db.insert('readings', reading.toMap());
      });
}

// Query for aggregated views
Future<List<Map<String, dynamic>>> getAveragesLastMinute(Database db) {
  final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
  return db.rawQuery(
    'SELECT sensor_id, AVG(value) as avg_value, MAX(value) as max_value '
    'FROM readings WHERE timestamp > ? '
    'GROUP BY sensor_id',
    [cutoff.millisecondsSinceEpoch],
  );
}
```

### Domain Object

```dart
class SensorReading {
  final String sensorId;
  final double value;
  final String unit;
  final DateTime timestamp;

  SensorReading({
    required this.sensorId,
    required this.value,
    required this.unit,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'sensorId': sensorId,
    'value': value,
    'unit': unit,
    'timestamp': timestamp.toIso8601String(),
  };

  factory SensorReading.fromJson(Map<String, dynamic> j) => SensorReading(
    sensorId: j['sensorId'] as String,
    value: (j['value'] as num).toDouble(),
    unit: j['unit'] as String,
    timestamp: DateTime.parse(j['timestamp'] as String),
  );

  Map<String, dynamic> toMap() => {
    'sensor_id': sensorId,
    'value': value,
    'unit': unit,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}
```

## Decision Checklist Applied

| Question | Answer for Sensor Readings |
|---|---|
| Is each record independently addressable? | No — readings are a stream of samples |
| Does data need to survive publisher going offline? | No — stale sensor readings are not useful |
| Is volume > ~10 writes/second? | Potentially yes |
| Primary query is a time-window aggregate? | Yes — averages, min/max over time windows |

All four answers point to **Notifications + SQLite**.

## When You Would Use AtCollection Instead

If your app also needs to store **device configuration** (alert thresholds, calibration settings, sensor metadata) that @device2 should be able to read, update, and have synced persistently — use `AtCollection<T>` for that data alongside the notification stream for the live readings:

```dart
// AtCollection for persistent config — synced across devices
final config = await atClient.collection<SensorConfig>(
  'config.my_app',
  const Duration(days: 365),
  fromJson: SensorConfig.fromJson,
  typeTag: 'SensorConfig',
);

await config.create(
  obj: SensorConfig(alertThreshold: 85.0, unit: 'celsius'),
  sharedWith: {'@device2'.toAtsign()},
);

// Notifications + SQLite for the live reading stream
// (as shown above)
```

Both patterns coexist naturally in the same app.

## Package Requirements

For a Dart CLI or IoT device (publisher):

```yaml
dependencies:
  at_client: ^3.12.0
```

For a Flutter app (subscriber with SQLite):

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  sqflite: ^2.0.0  # or drift / sqlite3
```

## Canonical Reference

The dockerstats example in the SDK demonstrates this exact pattern end-to-end:

- Publisher: `packages/at_client/example/bin/dockerstats_publish.dart`
- Flutter subscriber: `packages/at_client_flutter/examples/dockerstats/`

The publisher polls Docker stats every few seconds and sends them as notifications with a 5-minute expiration. The Flutter subscriber accumulates them in SQLite and renders charts. Sensor readings are structurally identical to this use case.
