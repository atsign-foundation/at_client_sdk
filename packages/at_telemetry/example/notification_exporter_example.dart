import 'dart:async';
import 'dart:convert';

import 'package:at_telemetry/at_telemetry.dart';

Future<void> main() async {
  final StreamController<(String, String)> notifications =
      StreamController<(String, String)>();
  final Future<void> received = _monitor(notifications.stream);
  final AtTelemetry telemetry = AtTelemetry(
    serviceName: 'my_app',
    exporter: AtTelemetryNotificationExporter(
      notify: (String idAndNamespace, String payload) async {
        notifications.add((idAndNamespace, payload));
      },
    ),
    onError: (Object error, StackTrace _) => print('Telemetry failed: $error'),
  );
  telemetry.event('app.started');
  telemetry.event(
    'app.connected',
    attributes: const <String, Object?>{'app.connections': 2},
  );
  await telemetry.shutdown();
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
