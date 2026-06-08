# Sharing Sensor Readings with @device2: Collection vs Notifications

For sharing sensor readings every few seconds with `@device2`, the right approach depends on what you mean by "notifications" and how the receiving side needs to consume the data.

## The Two Main Approaches

### 1. Self Keys / Shared Keys (atKey with value updates)

You create an `AtKey` shared with `@device2` and call `put()` every few seconds to update the value. The receiving side can either poll or subscribe to updates.

```dart
final key = AtKey()
  ..key = 'sensor_readings'
  ..sharedWith = '@device2'
  ..namespace = 'myapp';

// Every few seconds:
await atClient.put(key, jsonEncode(latestReadings));
```

On `@device2`, subscribe to changes:

```dart
atClient.notificationService.subscribe(
  regex: 'sensor_readings.myapp@mydevice',
).listen((notification) {
  final readings = jsonDecode(notification.value ?? '{}');
  // process readings
});
```

### 2. Notification Service (sendNotification)

You push each reading as a notification directly to `@device2`. The receiving side listens via `subscribe()`.

```dart
await atClient.notificationService.notify(
  NotificationParams.forUpdate(
    AtKey()
      ..key = 'sensor_update'
      ..sharedWith = '@device2'
      ..namespace = 'myapp',
    value: jsonEncode(latestReadings),
  ),
);
```

## Recommendation: Use Notifications for Frequent Sensor Data

For sensor readings sent every few seconds, **use the Notification Service** rather than updating a collection/shared key repeatedly.

### Why notifications are better here:

1. **Push semantics**: Notifications are delivered to `@device2` in near real-time without polling. The receiving atSign subscribes once and gets every update as it arrives.

2. **No stale data risk**: Each `put()` to a shared key overwrites the previous value. If `@device2` is briefly offline, it only sees the latest value when it reconnects — intermediate readings are lost. Notifications have a delivery retry mechanism.

3. **Event-driven on the receiver**: The subscriber callback fires on each notification, making it straightforward to process a stream of sensor events.

4. **Less overhead for frequent updates**: Updating a shared key every few seconds still triggers an internal notification to `@device2` anyway (the platform notifies the sharedWith atSign of key changes). Using `notificationService.notify()` directly is the explicit, intended pattern for this use case.

### When you would use a collection/shared key instead:

- You want `@device2` to query the **current state** on demand (e.g., "what is the sensor reading right now?")
- You want to store a **history** of readings as a list value under one key
- The updates are infrequent and `@device2` needs to read them asynchronously

## Practical Pattern for Frequent Sensor Data

Combine both if needed:

```dart
// Send notification for real-time delivery
await atClient.notificationService.notify(
  NotificationParams.forUpdate(
    AtKey()
      ..key = 'sensor'
      ..sharedWith = '@device2'
      ..namespace = 'sensors',
    value: jsonEncode({
      'temperature': 23.4,
      'humidity': 55.1,
      'timestamp': DateTime.now().toIso8601String(),
    }),
  ),
);
```

On `@device2`:

```dart
atClient.notificationService
    .subscribe(regex: 'sensor.sensors@mydevice')
    .listen((notification) {
  if (notification.operation == OperationEnum.update) {
    final data = jsonDecode(notification.value ?? '{}');
    print('Temp: ${data['temperature']}');
  }
});
```

## Summary

| Concern | Shared Key (put) | Notification Service |
|---|---|---|
| Real-time push delivery | Only if receiver subscribes | Yes, built-in |
| Intermediate values preserved | No (overwritten) | Yes (queued/retried) |
| Receiver must be online | No (reads latest on reconnect) | No (retry on reconnect) |
| Best for | Current state / on-demand reads | Streams of events / frequent updates |

**For your use case (every few seconds), use `notificationService.notify()`.**
