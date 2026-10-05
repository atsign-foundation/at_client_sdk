import 'at_telemetry_any_value.dart';
import 'at_telemetry_severity.dart';

// An OpenTelemetry LogRecord. A record with a non-empty eventName is an
// Event; without one it is a plain log. body and attribute values must be
// AnyValues (see AtTelemetryAnyValue).
final class AtTelemetryLogRecord {
  final String? eventName;
  final Object? body;
  final DateTime? timestamp;
  final AtTelemetrySeverity? severityNumber;
  final String? severityText;
  final Map<String, Object?> attributes;

  AtTelemetryLogRecord({
    this.eventName,
    this.body,
    DateTime? timestamp,
    this.severityNumber,
    this.severityText,
    Map<String, Object?> attributes = const <String, Object?>{},
  })  : timestamp = timestamp?.toUtc(),
        attributes = Map<String, Object?>.unmodifiable(attributes) {
    AtTelemetryAnyValue.check(body, 'body');
    for (final MapEntry<String, Object?> entry in attributes.entries) {
      AtTelemetryAnyValue.check(entry.value, 'attributes.${entry.key}');
    }
  }

  factory AtTelemetryLogRecord.fromJson(Map<String, Object?> json) {
    final Object? eventName = json['eventName'];
    final Object? timestamp = json['timestamp'];
    final Object? severityNumber = json['severityNumber'];
    final Object? severityText = json['severityText'];
    final Object attributes = json['attributes'] ?? const <String, Object?>{};
    if (eventName != null && eventName is! String) {
      throw const FormatException('eventName must be a string');
    }
    if (timestamp != null && timestamp is! String) {
      throw const FormatException('timestamp must be an ISO-8601 string');
    }
    if (severityNumber != null && severityNumber is! int) {
      throw const FormatException('severityNumber must be an integer');
    }
    if (severityText != null && severityText is! String) {
      throw const FormatException('severityText must be a string');
    }
    if (attributes is! Map<String, Object?>) {
      throw const FormatException('attributes must be a JSON object');
    }

    AtTelemetrySeverity? severity;
    if (severityNumber is int) {
      severity = AtTelemetrySeverity.fromNumber(severityNumber);
      if (severity == null) {
        throw const FormatException('severityNumber must be from 1 to 24');
      }
    }

    try {
      return AtTelemetryLogRecord(
        eventName: eventName as String?,
        body: json['body'],
        timestamp: timestamp is String ? DateTime.parse(timestamp) : null,
        severityNumber: severity,
        severityText: severityText as String?,
        attributes: attributes,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid log record: ${error.message}');
    }
  }

  bool get isEvent => eventName != null && eventName!.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (eventName != null) 'eventName': eventName,
      if (body != null) 'body': body,
      if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      if (severityNumber != null) 'severityNumber': severityNumber!.number,
      if (severityText != null) 'severityText': severityText,
      'attributes': attributes,
    };
  }
}
