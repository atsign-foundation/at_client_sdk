import 'package:at_telemetry/at_telemetry.dart';

import 'acme_gate_telemetry.dart';

const List<String> _levels = <String>[
  'Trace',
  'Debug',
  'Info',
  'Warning',
  'Error',
  'Fatal',
];

Future<void> main() async {
  final AtTelemetry telemetry = AtTelemetry(
    serviceName: AcmeGateTelemetry.serviceName,
    resourceAttributes: AtTelemetryResource.app(serviceVersion: '1.4.0'),
    exporter: AtTelemetryNotificationExporter(
      notify: _showOperatorView,
      enrollmentId: () => 'enrollment-1',
      clientId: () => AcmeGateTelemetry.serviceName,
    ),
    onError: (Object error, StackTrace _) => print('Telemetry failed: $error'),
  );
  final AcmeGateTelemetry gate = AcmeGateTelemetry(telemetry);

  gate.doorUnlocked(
    door: 'lobby',
    requestedBy: '@front_desk',
    took: const Duration(milliseconds: 840),
    commandNotificationId: 'n-101',
  );
  gate.doorRefused(
    door: 'loading_dock',
    requestedBy: '@front_desk',
    reason: 'outside_opening_hours',
    commandNotificationId: 'n-102',
  );
  gate.doorFailed(
    door: 'lobby',
    requestedBy: '@front_desk',
    commandNotificationId: 'n-103',
  );
  gate.doorFailed(
    door: 'lobby',
    requestedBy: '@night_guard',
    commandNotificationId: 'n-104',
  );
  gate.doorUnlocked(
    door: 'lobby',
    requestedBy: '@front_desk',
    took: const Duration(milliseconds: 910),
    commandNotificationId: 'n-105',
  );
  for (int update = 0; update < 5; update++) {
    gate.statusUnanswered(desk: '@front_desk');
  }
  gate.statusAnswered(desk: '@front_desk');

  await telemetry.shutdown();
}

Future<void> _showOperatorView(String idAndNamespace, String value) async {
  for (final AtTelemetryResourceLogs logs
      in const AtTelemetryLogsCodec().decode(value)) {
    for (final AtTelemetryLogRecord record in logs.records) {
      final AtTelemetrySeverity? severity = record.severityNumber;
      final String level =
          severity == null ? '' : _levels[(severity.number - 1) ~/ 4];
      final Object? anomalyKind =
          record.attributes[AcmeGateTelemetry.anomalyKindAttribute];
      final Object? anomalyMessage =
          record.attributes[AcmeGateTelemetry.anomalyMessageAttribute];
      print('${level.padRight(8)}${record.eventName}');
      if (anomalyKind != null) {
        print('        Anomaly: $anomalyKind: $anomalyMessage');
      }
      for (final MapEntry<String, Object?> attribute
          in record.attributes.entries) {
        if (attribute.key != AcmeGateTelemetry.anomalyKindAttribute &&
            attribute.key != AcmeGateTelemetry.anomalyMessageAttribute) {
          print('        ${attribute.key}: ${attribute.value}');
        }
      }
    }
  }
}
