import 'dart:async';
import 'dart:convert';

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
    eventName: 'app.started',
    timestamp: timestamp,
  ));
  await exporter.export(AtTelemetryLogRecord(
    eventName: 'app.connected',
    timestamp: timestamp,
    attributes: <String, Object?>{'app.connections': 2},
  ));
  await exporter.flush();
  await exporter.shutdown();
  await notifications.close();
  await received;
}

Future<void> _monitor(Stream<(String, String)> notifications) async {
  await for (final (String key, String payload) in notifications) {
    if (key == AtTelemetryNotificationExporter.idAndNamespace) {
      final AtTelemetryLogRecord logRecord = AtTelemetryLogRecord.fromJson(
        jsonDecode(payload) as Map<String, Object?>,
      );
      print('$key: ${logRecord.eventName}');
    }
  }
}
