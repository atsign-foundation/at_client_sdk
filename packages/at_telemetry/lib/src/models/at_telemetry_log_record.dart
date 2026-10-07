import '../utils/at_telemetry_type_checker.dart';
import 'at_telemetry_severity.dart';

// An OpenTelemetry LogRecord. A record with a non-empty eventName is an
// Event; without one it is a plain log. body and attribute values must be
// AnyValues (see AtTelemetryTypeChecker).
final class AtTelemetryLogRecord {
  // OTLP carries times as unsigned 64-bit nanoseconds since the Unix epoch,
  // which runs out in July 2554
  static final DateTime minTimestamp = DateTime.utc(1970);
  static final DateTime maxTimestamp = DateTime.utc(2554, 7, 21);

  final String? eventName;
  final Object? body;
  final DateTime? timestamp;
  final DateTime? observedTimestamp;
  final AtTelemetrySeverity? severityNumber;
  final String? severityText;
  final Map<String, Object?> attributes;

  AtTelemetryLogRecord({
    this.eventName,
    this.body,
    DateTime? timestamp,
    DateTime? observedTimestamp,
    this.severityNumber,
    this.severityText,
    Map<String, Object?> attributes = const <String, Object?>{},
  })  : timestamp = timestamp?.toUtc(),
        observedTimestamp = observedTimestamp?.toUtc(),
        attributes = Map<String, Object?>.unmodifiable(attributes) {
    _checkTimestamp(this.timestamp, 'timestamp');
    _checkTimestamp(this.observedTimestamp, 'observedTimestamp');
    AtTelemetryTypeChecker.check(body, 'body');
    for (final MapEntry<String, Object?> entry in attributes.entries) {
      AtTelemetryTypeChecker.check(entry.value, 'attributes.${entry.key}');
    }
  }

  bool get isEvent => eventName != null && eventName!.isNotEmpty;

  // A copy with extra attributes. An attribute already on the record wins.
  AtTelemetryLogRecord withDefaultAttributes(Map<String, Object?> defaults) {
    return AtTelemetryLogRecord(
      eventName: eventName,
      body: body,
      timestamp: timestamp,
      observedTimestamp: observedTimestamp,
      severityNumber: severityNumber,
      severityText: severityText,
      attributes: <String, Object?>{...defaults, ...attributes},
    );
  }

  static void _checkTimestamp(DateTime? value, String name) {
    if (value == null) {
      return;
    }
    if (value.isBefore(minTimestamp) || value.isAfter(maxTimestamp)) {
      throw ArgumentError.value(
        value,
        name,
        'must be between $minTimestamp and $maxTimestamp',
      );
    }
  }
}
