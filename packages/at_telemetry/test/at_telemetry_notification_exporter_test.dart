import 'dart:async';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
  final DateTime timestamp = DateTime.utc(2026, 9, 29, 12);
  final AtTelemetryLogRecord log = AtTelemetryLogRecord(
    name: 'app.started',
    timestamp: timestamp,
    attributes: const <String, Object?>{'version': '1.2.3'},
  );
  final AtTelemetryLogRecord connected = AtTelemetryLogRecord(
    name: 'app.connected',
    timestamp: timestamp,
    attributes: const <String, Object?>{'app.connections': 2},
  );

  late List<(String, String)> notifications;
  late AtTelemetryNotificationExporter exporter;

  setUp(() {
    notifications = <(String, String)>[];
    exporter = AtTelemetryNotificationExporter(
      serviceName: 'my_app',
      notify: (String key, String payload) async {
        notifications.add((key, payload));
      },
    );
  });

  tearDown(() async {
    await exporter.shutdown();
  });

  test('exports logs as base64 OTLP notifications', () async {
    await exporter.export(log);
    await exporter.export(connected);
    await exporter.flush();

    expect(notifications.map(((String, String) item) => item.$1), <String>[
      'logs.at_telemetry',
      'logs.at_telemetry',
    ]);
    final AtTelemetryLogRecord actualLog =
        codec.decode(notifications[0].$2).single;
    final AtTelemetryLogRecord actualConnected =
        codec.decode(notifications[1].$2).single;
    expect(actualLog.name, log.name);
    expect(actualLog.timestamp, timestamp);
    expect(actualLog.attributes['version'], '1.2.3');
    expect(actualConnected.name, 'app.connected');
    expect(actualConnected.attributes['app.connections'], 2);
    for (final AtTelemetryLogRecord record in <AtTelemetryLogRecord>[
      actualLog,
      actualConnected,
    ]) {
      expect(record.attributes['service.name'], 'my_app');
    }
  });

  test('serializes sends and flush waits for queued notifications', () async {
    final Completer<void> started = Completer<void>();
    final Completer<void> release = Completer<void>();
    exporter = AtTelemetryNotificationExporter(
      serviceName: 'my_app',
      notify: (String key, String payload) async {
        notifications.add((key, payload));
        if (notifications.length == 1) {
          started.complete();
          await release.future;
        }
      },
    );
    final Future<void> first = exporter.export(log);
    final Future<void> second = exporter.export(connected);
    bool flushed = false;
    final Future<void> flush = exporter.flush().then((_) => flushed = true);
    await started.future;
    expect(notifications, hasLength(1));
    expect(flushed, isFalse);
    release.complete();
    await Future.wait<void>(<Future<void>>[first, second, flush]);
    expect(notifications, hasLength(2));
    expect(flushed, isTrue);
  });

  test('snapshots queued log attributes', () async {
    final Map<String, Object?> attributes = <String, Object?>{'room': 'lab'};
    final Future<void> sent = exporter.export(AtTelemetryLogRecord(
      name: 'temperature.read',
      timestamp: timestamp,
      attributes: attributes,
    ));
    attributes['room'] = 'office';
    await sent;
    expect(codec.decode(notifications.single.$2).single.attributes,
        <String, Object?>{'room': 'lab', 'service.name': 'my_app'});
  });

  test('reports failed sends and keeps later exports usable', () async {
    int attempts = 0;
    exporter = AtTelemetryNotificationExporter(
      serviceName: 'my_app',
      notify: (String key, String payload) async {
        if (attempts++ == 0) {
          throw StateError('Notify unavailable');
        }
        notifications.add((key, payload));
      },
    );
    await expectLater(exporter.export(log), throwsStateError);
    await expectLater(exporter.flush(), throwsStateError);
    await exporter.export(connected);
    await exporter.flush();
    expect(notifications, hasLength(1));
  });

  test('shutdown drains pending sends and rejects further exports', () async {
    final Future<void> sent = exporter.export(log);
    final Future<void> shutdown = exporter.shutdown();
    await expectLater(exporter.export(log), throwsStateError);
    await expectLater(exporter.export(connected), throwsStateError);
    await Future.wait<void>(<Future<void>>[sent, shutdown]);
    expect(notifications, hasLength(1));
    await exporter.shutdown();
  });

  test('rejects invalid logs before sending', () async {
    await expectLater(
        exporter.export(AtTelemetryLogRecord(name: '', timestamp: timestamp)),
        throwsArgumentError);
    expect(notifications, isEmpty);
  });

  test('bounds notification size and discards the oldest queued sends',
      () async {
    exporter = AtTelemetryNotificationExporter(
      serviceName: 'my_app',
      maxPayloadCharacters: 1,
      notify: (String key, String payload) async {
        fail('Oversized payload must not be sent');
      },
    );
    await expectLater(exporter.export(log), throwsArgumentError);
    await exporter.shutdown();

    final Completer<void> release = Completer<void>();
    final List<String> delivered = <String>[];
    exporter = AtTelemetryNotificationExporter(
      serviceName: 'my_app',
      maxQueuedExports: 1,
      notify: (String key, String payload) async {
        await release.future;
        delivered.add(codec.decode(payload).single.name);
      },
    );
    AtTelemetryLogRecord named(String name) =>
        AtTelemetryLogRecord(name: name, timestamp: timestamp);

    final Future<void> inFlight = exporter.export(named('in.flight'));
    final Future<void> oldest = exporter.export(named('oldest'));
    final Future<void> newest = exporter.export(named('newest'));

    await expectLater(oldest, throwsStateError);
    release.complete();
    await Future.wait<void>(<Future<void>>[inFlight, newest]);
    await expectLater(exporter.flush(), throwsStateError);
    expect(delivered, <String>['in.flight', 'newest']);

    await exporter.export(named('after.drain'));
    await exporter.flush();
    expect(delivered.last, 'after.drain');
  });

  test('validates configuration', () {
    for (final (String, int, int) configuration in <(String, int, int)>[
      (' ', 1, 1),
      ('my_app', 0, 1),
      ('my_app', 1, 0),
    ]) {
      expect(
        () => AtTelemetryNotificationExporter(
          serviceName: configuration.$1,
          maxQueuedExports: configuration.$2,
          maxPayloadCharacters: configuration.$3,
          notify: (String key, String payload) async {},
        ),
        throwsArgumentError,
      );
    }
  });
}
