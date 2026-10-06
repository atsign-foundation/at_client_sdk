import 'dart:async';

import 'package:at_telemetry/at_telemetry.dart';

// Run with: dart run example/notification_exporter_example.dart
Future<void> main() async {
  final StreamController<(String, String)> notifications =
      StreamController<(String, String)>();
  final Future<void> received = _monitor(notifications.stream);
  final AtTelemetry telemetry = AtTelemetry(
    serviceName: 'my_app',
    exporter: AtTelemetryNotificationExporter(
      notify: (String idAndNamespace, String value) async {
        notifications.add((idAndNamespace, value));
      },
      enrollmentId: () => 'enrollment-1',
      clientId: () => 'client-1',
    ),
    onError: (Object error, StackTrace _) => print('Telemetry failed: $error'),
  );
  telemetry.event('photos.album.shared', notificationIds: <String>['n7']);
  telemetry.event(
    'photos.album.viewed',
    attributes: const <String, Object?>{'album.photoCount': 12},
  );
  await telemetry.shutdown();
  await notifications.close();
  await received;
}

Future<void> _monitor(Stream<(String, String)> notifications) async {
  await for (final (String key, String value) in notifications) {
    if (key != AtTelemetryNotificationExporter.idAndNamespace) {
      continue;
    }
    for (final AtTelemetryResourceLogs logs
        in const AtTelemetryLogsCodec().decode(value)) {
      for (final AtTelemetryLogRecord record in logs.records) {
        print('$key: ${record.eventName} ${record.attributes}');
      }
    }
  }
}
