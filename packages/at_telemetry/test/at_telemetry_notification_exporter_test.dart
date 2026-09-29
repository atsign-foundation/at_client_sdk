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
  final AtTelemetryGauge metric = AtTelemetryGauge(
    name: 'app.connections',
    value: 2,
    timestamp: timestamp,
  );
  final AtTelemetrySpan span = AtTelemetrySpan(
    name: 'app.connect',
    traceId: '0123456789abcdef0123456789abcdef',
    spanId: '0123456789abcdef',
    startTimestamp: timestamp,
    endTimestamp: timestamp.add(const Duration(milliseconds: 10)),
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

  test('exports all three signals as base64 OTLP notifications', () async {
    await exporter.export(log);
    await exporter.exportMetrics(<AtTelemetryMetric>[metric]);
    await exporter.exportSpans(<AtTelemetrySpan>[span]);
    await exporter.flush();

    expect(notifications.map(((String, String) item) => item.$1), <String>[
      'logs.at_telemetry',
      'metrics.at_telemetry',
      'traces.at_telemetry',
    ]);
    final AtTelemetryLogRecord actualLog =
        codec.decode(notifications[0].$2).single;
    final AtTelemetryGauge actualMetric =
        codec.decodeMetrics(notifications[1].$2).single as AtTelemetryGauge;
    final AtTelemetrySpan actualSpan =
        codec.decodeSpans(notifications[2].$2).single;
    expect(actualLog.name, log.name);
    expect(actualLog.timestamp, timestamp);
    expect(actualLog.attributes['version'], '1.2.3');
    expect(actualMetric.name, metric.name);
    expect(actualMetric.value, 2);
    expect(actualSpan.traceId, span.traceId);
    expect(actualSpan.spanId, span.spanId);
    for (final Map<String, Object?> attributes in <Map<String, Object?>>[
      actualLog.attributes,
      actualMetric.attributes,
      actualSpan.attributes,
    ]) {
      expect(attributes['service.name'], 'my_app');
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
    final Future<void> second =
        exporter.exportMetrics(<AtTelemetryMetric>[metric]);
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

  test('snapshots queued measurements and their attributes', () async {
    final Map<String, Object?> attributes = <String, Object?>{'room': 'lab'};
    final List<AtTelemetryMetric> measurements = <AtTelemetryMetric>[
      AtTelemetryGauge(
        name: 'temperature',
        value: 20,
        timestamp: timestamp,
        attributes: attributes,
      ),
    ];
    final Future<void> sent = exporter.exportMetrics(measurements);
    measurements.clear();
    attributes['room'] = 'office';
    await sent;
    expect(codec.decodeMetrics(notifications.single.$2).single.attributes,
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
    await exporter.exportMetrics(<AtTelemetryMetric>[metric]);
    await exporter.flush();
    expect(notifications, hasLength(1));
  });

  test('shutdown drains pending sends and rejects further exports', () async {
    final Future<void> sent = exporter.export(log);
    final Future<void> shutdown = exporter.shutdown();
    await expectLater(exporter.export(log), throwsStateError);
    await expectLater(
        exporter.exportMetrics(<AtTelemetryMetric>[metric]), throwsStateError);
    await expectLater(
        exporter.exportSpans(<AtTelemetrySpan>[span]), throwsStateError);
    await Future.wait<void>(<Future<void>>[sent, shutdown]);
    expect(notifications, hasLength(1));
    await exporter.shutdown();
  });

  test('rejects empty batches and invalid logs before sending', () async {
    await expectLater(
        exporter.exportMetrics(<AtTelemetryMetric>[]), throwsArgumentError);
    await expectLater(
        exporter.exportSpans(<AtTelemetrySpan>[]), throwsArgumentError);
    await expectLater(
        exporter.export(AtTelemetryLogRecord(name: '', timestamp: timestamp)),
        throwsArgumentError);
    expect(notifications, isEmpty);
  });

  test('bounds notification size and pending sends', () async {
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
    exporter = AtTelemetryNotificationExporter(
      serviceName: 'my_app',
      maxPendingExports: 1,
      notify: (String key, String payload) => release.future,
    );
    final Future<void> sent = exporter.export(log);
    await expectLater(exporter.export(log), throwsStateError);
    release.complete();
    await sent;
    await exporter.flush();
    await exporter.export(log);
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
          maxPendingExports: configuration.$2,
          maxPayloadCharacters: configuration.$3,
          notify: (String key, String payload) async {},
        ),
        throwsArgumentError,
      );
    }
  });
}
