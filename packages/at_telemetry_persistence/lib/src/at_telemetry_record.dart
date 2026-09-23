import 'package:at_telemetry/at_telemetry.dart';

final class AtTelemetryRecord {
  final int id;
  final String tenantId;
  final AtTelemetryEvent event;
  final DateTime receivedAt;

  const AtTelemetryRecord({
    required this.id,
    required this.tenantId,
    required this.event,
    required this.receivedAt,
  });
}
