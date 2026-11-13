---
name: at-telemetry-app-events
description: >
  Use when adding at_telemetry to a Dart or Flutter app built on the Atsign
  Protocol, or when deciding what an app should report to the Atsign Control
  Center. Covers which info events to send for intentional actions, which
  error events should flag the Control Center operator with anomaly.kind and
  anomaly.message, how to name events and attributes, which severity to use,
  how to link an event to the notification it sent or received, and what not
  to send because the atServer already reports it (message volume between
  endpoints, connections, authentication, enrollments, notification
  delivery).
license: BSD-3-Clause
compatibility: Claude Code and any agentskills.io-compatible agent.
metadata:
  version: "0.1.1"
---

# App telemetry for the Atsign Control Center

> **Audience:** an AI coding agent adding `at_telemetry` to an app whose
> endpoints (one atSign each) are managed from the Atsign Control Center.

## 1. Who reads this telemetry

The **Control Center operator**. They run a fleet of endpoints: devices,
services and user apps, one atSign each. They want to know two things:

- what each endpoint is doing, in the app's own words: "lobby door unlocked
  for @front_desk"
- when an endpoint cannot do its job, and what to check

They do not know or care how the Atsign Protocol works. Keys, sync, PKAM,
enrollments, atServer connections and notification delivery mean nothing to
them.

The atServer **already reports** protocol activity, including how many
messages go between which endpoints and whether they were delivered. So the
app reports only what the atServer cannot know:

1. **what a message meant**, and
2. **when the app could not do its job.**

## 2. Send exactly two kinds of record

| Kind | When | Call | Operator sees |
| --- | --- | --- | --- |
| Intent event | The app finished something a person or device asked for, on purpose | `telemetry.event(name, severity: AtTelemetrySeverity.info, ...)` | A row in Activity with Level `Info` |
| Operator anomaly | The app cannot do its job and a person needs to act | `telemetry.event(name, severity: AtTelemetrySeverity.error, ...)` with `anomaly.kind` and `anomaly.message` attributes | A red **Anomaly** chip, and `kind: message` on the event's page |

One optional middle tier: `warn` **without** anomaly attributes, for an
outcome the user did not get but nobody has to fix, such as a command refused
by a business rule.

Everything else is noise. Do not send debug logs, one record per retry,
heartbeats, or stack traces.

## 3. Set up once per process

```dart
import 'package:at_client/at_client.dart';
import 'package:at_telemetry/at_telemetry.dart';

final AtTelemetry telemetry = AtTelemetry(
  serviceName: 'acme_gate',
  resourceAttributes: AtTelemetryResource.app(serviceVersion: '1.4.0'),
  exporter: AtTelemetryNotificationExporter(
    notify: (String idAndNamespace, String value) async {
      await atClient.notificationService.send(
        to: Atsign(settings.telemetryCollector),
        idAndNamespace: idAndNamespace,
        body: value,
      );
    },
    enrollmentId: () => atClient.enrollmentId,
    clientId: () => atClient.getPreferences()?.atClientParticulars.clientId,
  ),
);
```

Call `await telemetry.shutdown();` before the process exits, or the events
still waiting in the current batch are lost.

- `serviceName` is the app's stable name in snake_case, the same on every
  endpoint that runs the app. It is **not** the atSign: the collector records
  which atSign sent each batch by itself.
- `serviceVersion` is the app's version. The Control Center shows it next to
  the service name.
- The collector atSign is chosen by the operator. Read it from configuration.
- The endpoint's atSign must be registered with the operator's collector, or
  its telemetry is dropped. That is set up on the Control Center side, not in
  the app.
- `event` returns at once and never throws for a delivery problem. It **does**
  throw `ArgumentError` for an attribute value of the wrong type (section 7).

## 4. Put the whole vocabulary in one class

Create one class, in its own file, that owns every event name, attribute name
and anomaly kind the app sends, plus the state that decides when an anomaly
fires. The rest of the app calls methods like `gateTelemetry.doorUnlocked(...)`
and never calls `telemetry.event` itself.

```dart
final class AcmeGateTelemetry {
  static const String unlockedEvent = 'acme_gate.door.unlocked';
  static const String failedEvent = 'acme_gate.door.failed';
  static const String recoveredEvent = 'acme_gate.door.recovered';

  static const String doorAttribute = 'acme_gate.door.id';
  static const String requestedByAttribute = 'acme_gate.command.from';
  static const String durationAttribute = 'acme_gate.unlock.duration_ms';
  static const String failedCommandsAttribute =
      'acme_gate.door.failed_commands';
  static const String anomalyKindAttribute = 'anomaly.kind';
  static const String anomalyMessageAttribute = 'anomaly.message';

  static const String deviceFault = 'device_fault';

  final AtTelemetry _telemetry;
  final Map<String, int> _failedCommands = <String, int>{};

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
}
```

The full version, with a business-rule `warn` and a peer that stops
answering, is in
[references/acme-gate-example.md](references/acme-gate-example.md). The
package also ships it as a runnable example:
`dart run example/control_center_app_example.dart`.

## 5. Name events `<app>.<thing>.<outcome>`

Good: `acme_gate.door.unlocked`, `coldchain.sensor.calibrated`,
`backup.snapshot.completed`, `orders.order.accepted`.

- **Start with the app's own prefix**, normally its `serviceName`. Never start
  with `atsign.`: that namespace belongs to Atsign, and the atServer's own
  events are `atsign.atserver.*`.
- Lowercase, dot separated, snake_case inside a segment.
- **Fixed strings only.** Never put an atSign, id, count or free text in a
  name. The Activity page lists events by name, and a name with a variable in
  it becomes thousands of one-off names. Variables go in attributes.
- **Use `event`, never `log`.** A plain log has no name, so the Control Center
  shows its whole text where the name should be.

## 6. Always set the severity

| Severity | Use for | Anomaly attributes |
| --- | --- | --- |
| `AtTelemetrySeverity.info` | An intent finished. A condition recovered. | No |
| `AtTelemetrySeverity.warn` | The user did not get what they asked for, but the app is fine and nobody has to act | No |
| `AtTelemetrySeverity.error` | The app cannot do its job and a person should act | **Yes** |
| `AtTelemetrySeverity.fatal` | The app is stopping because of it | **Yes** |

Without a severity, the Level column in the Control Center is blank.

## 7. Attributes

- **Name them `<app>.<thing>.<property>`**, such as `acme_gate.door.id` or
  `acme_gate.unlock.duration_ms`. The Control Center shows
  `acme_gate.door.id` as "Acme gate door ID", so names should still read well
  that way.
- **Name the other endpoint.** Whenever an event involves another endpoint,
  put that endpoint's atSign in an attribute whose name says its role:
  `acme_gate.command.from`, `coldchain.reading.hub`. Which endpoint talks to
  which is what operators care about most.
- **Short scalar values:** strings under 64 characters, `int`, `bool`, finite
  `double`. Put the unit in the name: `_ms`, `_bytes`, `_count`. Lists and
  maps are allowed but hard to read in the Control Center.
- Any other value type (a `DateTime`, an enum, an `Atsign`, an exception)
  throws `ArgumentError`. Convert it to a `String` first.
- **Never set these yourself:** anything under `atsign.`, `service.`,
  `at_telemetry.`, `tenant.id` or `event_name`. The exporter and the collector
  set them, and the collector overwrites some of them.
- `body` is optional. Leave it empty and put the details in attributes.

## 8. Link to the message, never re-count it

When an event is caused by, or causes, a notification, pass its id:

- received: `notificationIds: <String>[notification.id]`
- sent: `notificationIds: <String>[await atClient.notificationService.send(...)]`
- atKeys the event wrote or read: `keys: <String>[atKey.toString()]`

The Control Center can then line the app's event up with the atServer's
delivery record for the same message.

**Never** send an event that only says a message was sent, received or
delivered, or a count of messages. The test: if the event would be one to one
with a notification and says nothing the notification does not, drop it.

## 9. Operator anomalies

An anomaly is an `error` (or `fatal`) event with two extra attributes:

| Attribute | Value |
| --- | --- |
| `anomaly.kind` | A short snake_case category from a small, fixed list the app defines, stable across versions. Operators group by it. |
| `anomaly.message` | One or two sentences in the operator's words: what is wrong, on which endpoint or with which peer, and what to check. |

Rules:

1. **Only when a person can and should act.** If the app recovers by itself,
   it is `warn`, or nothing.
2. **Good kinds:** `device_fault`, `peer_unresponsive`, `command_rejected`,
   `config_invalid`, `storage_full`, `backlog_growing`, `overdue`.
   **Bad kinds:** `error`, `SocketException`, `AtTimeoutException`, anything
   with an id or atSign in it.
3. **Good message:** "@front_desk has not answered the last 3 door status
   updates. Check that the front desk app is running."
   **Bad message:** exception text, a stack trace, key names, or protocol
   words like PKAM, sync, enrollment or atServer.
4. **Fire on change, not on every failure.** Send the anomaly once when a
   condition starts. When it clears, send a matching `<thing>.recovered`
   `info` event, without anomaly attributes, saying how many attempts it
   affected. Keep at most one open anomaly per condition per endpoint or peer.
5. **Describe the condition in app terms.** "The front desk stopped answering
   door status updates", not "notification to @front_desk errored". If all
   the app knows is that a notification failed, the atServer has already
   reported it: send nothing.
6. **Not for a lost connection to the app's own atServer.** Telemetry goes out
   through that atServer, so such an anomaly only arrives once the connection
   is back, too late to alert anyone.
7. **Business alerts the app already shows its users are not anomalies.** A
   fridge that is too warm is a `warn` event from a working sensor. A sensor
   that stopped reading is the anomaly.
8. **When an endpoint goes silent, its peer reports it.** A stopped app sends
   nothing, so the endpoint that expected to hear from it raises
   `peer_unresponsive` or `overdue`, naming the silent endpoint's atSign.

## 10. Never send

Already reported by the atServer. Sending these again double-counts them:

- messages between endpoints: sent, delivered, errored, expired, retried, or
  counts of any of them
- connections opened, authenticated, monitoring or closed
- authentication failures
- enrollment requests, approvals, denials, revocations and deletions
- refused requests and failed verbs
- atServer start, stop and heartbeat

Not for the operator:

- sync progress, key and encryption operations, onboarding steps
- debug or trace output, one record per retry, periodic "still alive" events
- message content, personal data, file contents, secrets, tokens, raw
  exception text, stack traces

## 11. Checklist

- [ ] One `AtTelemetry` per process, and `await telemetry.shutdown()` on exit
- [ ] All event and attribute names live in one telemetry class
- [ ] Every event name is a fixed `<app>.<thing>.<outcome>` string, not
      starting with `atsign.`
- [ ] Every event sets a severity
- [ ] Every event that involves another endpoint names its atSign
- [ ] Events tied to a notification pass `notificationIds`
- [ ] No event only restates that a message was sent, received or delivered
- [ ] Every `error` and `fatal` event has `anomaly.kind` and
      `anomaly.message`, and no `info` or `warn` event has them
- [ ] Anomalies fire once when a condition starts, with a `recovered` event
      when it clears
- [ ] No message content, personal data, secrets, exception text or stack
      traces anywhere

## 12. More examples

[references/event-catalogs.md](references/event-catalogs.md) has the full
event list for four kinds of app: a remote-controlled device, a sensor that
reports to a hub, a chat app, and a backup agent.
