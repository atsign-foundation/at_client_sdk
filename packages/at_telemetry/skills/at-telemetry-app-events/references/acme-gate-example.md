# Worked example: acme_gate

`acme_gate` runs on door controllers. Each controller is an endpoint with its
own atSign. A front desk app (`@front_desk`) sends it unlock commands as
notifications, and the controller sends door status updates back, which the
front desk answers.

The package ships this as a runnable example:

```sh
dart run example/control_center_app_example.dart
```

## What it reports, and why

| Situation | Record | Why |
| --- | --- | --- |
| A door unlocks for a command | `info` `acme_gate.door.unlocked`, naming the door, who asked, how long it took, and the command's notification id | Intent: tells the operator what the command meant |
| A command is refused by a business rule | `warn` `acme_gate.door.refused` with the reason | The user did not get what they asked for, but nothing is broken |
| A door does not open | `error` `acme_gate.door.failed` with `anomaly.kind: device_fault`, **once** per fault | A person has to check the motor |
| The same door fails again | nothing | The anomaly is already open |
| The faulty door opens again | `info` `acme_gate.door.recovered`, with how many commands failed, then `acme_gate.door.unlocked` | Closes the anomaly |
| The front desk stops answering status updates, 3 in a row | `error` `acme_gate.desk.unresponsive` with `anomaly.kind: peer_unresponsive`, **once** | The atServer sees the updates delivered; only the app knows nobody answers |
| The front desk answers again | `info` `acme_gate.desk.recovered` | Closes the anomaly |
| A status update is sent | nothing | The atServer already counts it |

## The telemetry class

```dart
import 'package:at_telemetry/at_telemetry.dart';

final class AcmeGateTelemetry {
  static const String serviceName = 'acme_gate';

  static const String unlockedEvent = 'acme_gate.door.unlocked';
  static const String refusedEvent = 'acme_gate.door.refused';
  static const String failedEvent = 'acme_gate.door.failed';
  static const String recoveredEvent = 'acme_gate.door.recovered';
  static const String deskUnresponsiveEvent = 'acme_gate.desk.unresponsive';
  static const String deskRecoveredEvent = 'acme_gate.desk.recovered';

  static const String doorAttribute = 'acme_gate.door.id';
  static const String requestedByAttribute = 'acme_gate.command.from';
  static const String durationAttribute = 'acme_gate.unlock.duration_ms';
  static const String refusedReasonAttribute = 'acme_gate.refused.reason';
  static const String failedCommandsAttribute =
      'acme_gate.door.failed_commands';
  static const String deskAttribute = 'acme_gate.desk';
  static const String unansweredAttribute = 'acme_gate.desk.unanswered_updates';
  static const String anomalyKindAttribute = 'anomaly.kind';
  static const String anomalyMessageAttribute = 'anomaly.message';

  static const String deviceFault = 'device_fault';
  static const String peerUnresponsive = 'peer_unresponsive';

  static const int unansweredLimit = 3;

  final AtTelemetry _telemetry;
  final Map<String, int> _failedCommands = <String, int>{};
  final Map<String, int> _unansweredUpdates = <String, int>{};

  AcmeGateTelemetry(this._telemetry);

  void doorUnlocked({
    required String door,
    required String requestedBy,
    required Duration took,
    required String commandNotificationId,
  }) {
    final int? failedCommands = _failedCommands.remove(door);
    if (failedCommands != null) {
      _telemetry.event(
        recoveredEvent,
        severity: AtTelemetrySeverity.info,
        attributes: <String, Object?>{
          doorAttribute: door,
          failedCommandsAttribute: failedCommands,
        },
      );
    }
    _telemetry.event(
      unlockedEvent,
      severity: AtTelemetrySeverity.info,
      attributes: <String, Object?>{
        doorAttribute: door,
        requestedByAttribute: requestedBy,
        durationAttribute: took.inMilliseconds,
      },
      notificationIds: <String>[commandNotificationId],
    );
  }

  void doorRefused({
    required String door,
    required String requestedBy,
    required String reason,
    required String commandNotificationId,
  }) {
    _telemetry.event(
      refusedEvent,
      severity: AtTelemetrySeverity.warn,
      attributes: <String, Object?>{
        doorAttribute: door,
        requestedByAttribute: requestedBy,
        refusedReasonAttribute: reason,
      },
      notificationIds: <String>[commandNotificationId],
    );
  }

  void doorFailed({
    required String door,
    required String requestedBy,
    required String commandNotificationId,
  }) {
    final int failedCommands = (_failedCommands[door] ?? 0) + 1;
    _failedCommands[door] = failedCommands;
    if (failedCommands > 1) {
      return;
    }
    _telemetry.event(
      failedEvent,
      severity: AtTelemetrySeverity.error,
      attributes: <String, Object?>{
        doorAttribute: door,
        requestedByAttribute: requestedBy,
        anomalyKindAttribute: deviceFault,
        anomalyMessageAttribute: 'The $door door did not open when '
            '$requestedBy unlocked it. Check the door motor and its power.',
      },
      notificationIds: <String>[commandNotificationId],
    );
  }

  void statusUnanswered({required String desk}) {
    final int unanswered = (_unansweredUpdates[desk] ?? 0) + 1;
    _unansweredUpdates[desk] = unanswered;
    if (unanswered != unansweredLimit) {
      return;
    }
    _telemetry.event(
      deskUnresponsiveEvent,
      severity: AtTelemetrySeverity.error,
      attributes: <String, Object?>{
        deskAttribute: desk,
        unansweredAttribute: unanswered,
        anomalyKindAttribute: peerUnresponsive,
        anomalyMessageAttribute: '$desk has not answered the last $unanswered '
            'door status updates. Check that the front desk app is running.',
      },
    );
  }

  void statusAnswered({required String desk}) {
    final int? unanswered = _unansweredUpdates.remove(desk);
    if (unanswered == null || unanswered < unansweredLimit) {
      return;
    }
    _telemetry.event(
      deskRecoveredEvent,
      severity: AtTelemetrySeverity.info,
      attributes: <String, Object?>{
        deskAttribute: desk,
        unansweredAttribute: unanswered,
      },
    );
  }
}
```

## Calling it from the app

The app calls the class where the work happens, never `telemetry.event`
directly:

```dart
atClient.notificationService
    .subscribe(regex: 'unlock.acme_gate', shouldDecrypt: true)
    .listen((AtNotification command) async {
  final String door = command.value!;
  final Stopwatch stopwatch = Stopwatch()..start();
  if (!schedule.isOpen(door)) {
    gateTelemetry.doorRefused(
      door: door,
      requestedBy: command.from,
      reason: 'outside_opening_hours',
      commandNotificationId: command.id,
    );
    return;
  }
  if (await motor.open(door)) {
    gateTelemetry.doorUnlocked(
      door: door,
      requestedBy: command.from,
      took: stopwatch.elapsed,
      commandNotificationId: command.id,
    );
  } else {
    gateTelemetry.doorFailed(
      door: door,
      requestedBy: command.from,
      commandNotificationId: command.id,
    );
  }
});
```

## What the operator sees

Output of the runnable example, one record per block, in the order they were
sent. The Control Center lists them newest first.

```text
Info    acme_gate.door.unlocked
        atsign.enrollment.id: enrollment-1
        atsign.client.id: acme_gate
        acme_gate.door.id: lobby
        acme_gate.command.from: @front_desk
        acme_gate.unlock.duration_ms: 840
        atsign.notification.ids: [n-101]
Warning acme_gate.door.refused
        ...
        acme_gate.refused.reason: outside_opening_hours
Error   acme_gate.door.failed
        Anomaly: device_fault: The lobby door did not open when @front_desk unlocked it. Check the door motor and its power.
        ...
Info    acme_gate.door.recovered
        ...
        acme_gate.door.failed_commands: 2
Info    acme_gate.door.unlocked
        ...
Error   acme_gate.desk.unresponsive
        Anomaly: peer_unresponsive: @front_desk has not answered the last 3 door status updates. Check that the front desk app is running.
        ...
Info    acme_gate.desk.recovered
        ...
```

The exporter adds `atsign.enrollment.id` and `atsign.client.id` to every
record, and `notificationIds` becomes `atsign.notification.ids`. The app sets
none of those three by hand.
