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

  factory AtTelemetryRecord.fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? tenantId = json['tenantId'];
    final Object? event = json['event'];
    final Object? receivedAt = json['receivedAt'];
    if (id is! int) {
      throw const FormatException('Record id must be an integer');
    }
    if (tenantId is! String || tenantId.trim().isEmpty) {
      throw const FormatException('Record tenantId must be a non-empty string');
    }
    if (event is! Map<String, Object?>) {
      throw const FormatException('Record event must be a JSON object');
    }
    if (receivedAt is! String) {
      throw const FormatException(
        'Record receivedAt must be an ISO-8601 string',
      );
    }

    return AtTelemetryRecord(
      id: id,
      tenantId: tenantId,
      event: AtTelemetryEvent.fromJson(event),
      receivedAt: DateTime.parse(receivedAt).toUtc(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'tenantId': tenantId,
      'event': event.toJson(),
      'receivedAt': receivedAt.toUtc().toIso8601String(),
    };
  }
}
