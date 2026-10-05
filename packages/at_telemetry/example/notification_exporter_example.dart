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
  await exporter.export(AtTelemetryLogRecord(
    name: 'app.connected',
    timestamp: timestamp,
    attributes: <String, Object?>{'app.connections': 2},
  ));
  await exporter.flush();
  await exporter.shutdown();
  await notifications.close();
  await received;
}

Future<void> _monitor(Stream<(String, String)> notifications) async {
  const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
  await for (final (String key, String payload) in notifications) {
    if (key == AtTelemetryNotificationCodec.idAndNamespace) {
      print('$key: ${codec.decode(payload).single.name}');
    }
  }
}
