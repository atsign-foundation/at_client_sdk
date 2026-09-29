import 'dart:async';

import 'package:at_telemetry/at_telemetry.dart';

Future<void> main() async {
  final StreamController<(String, String)> notifications =
      StreamController<(String, String)>();
  final Future<void> received = _monitor(notifications.stream);
  final AtTelemetryNotificationExporter exporter =
      AtTelemetryNotificationExporter(
    serviceName: 'my_app',
    notify: (String idAndNamespace, String payload) async {
      notifications.add((idAndNamespace, payload));
    },
  );
  final DateTime timestamp = DateTime.now().toUtc();
  await exporter.export(AtTelemetryLogRecord(
    name: 'app.started',
    timestamp: timestamp,
  ));
  await exporter.exportMetrics(<AtTelemetryMetric>[
    AtTelemetryGauge(name: 'app.connections', value: 2, timestamp: timestamp),
  ]);
  await exporter.exportSpans(<AtTelemetrySpan>[
    AtTelemetrySpan(
      name: 'app.connect',
      traceId: '0123456789abcdef0123456789abcdef',
      spanId: '0123456789abcdef',
      startTimestamp: timestamp,
      endTimestamp: timestamp.add(const Duration(milliseconds: 10)),
    ),
  ]);
  await exporter.flush();
  await exporter.shutdown();
  await notifications.close();
  await received;
}

Future<void> _monitor(Stream<(String, String)> notifications) async {
  const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
  await for (final (String key, String payload) in notifications) {
    switch (key) {
      case AtTelemetryNotificationCodec.idAndNamespace:
        print('$key: ${codec.decode(payload).single.name}');
      case AtTelemetryNotificationCodec.metricsIdAndNamespace:
        print('$key: ${codec.decodeMetrics(payload).single.name}');
      case AtTelemetryNotificationCodec.tracesIdAndNamespace:
        print('$key: ${codec.decodeSpans(payload).single.name}');
    }
  }
}
