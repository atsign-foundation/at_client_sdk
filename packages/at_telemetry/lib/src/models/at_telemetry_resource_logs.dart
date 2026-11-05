import '../utils/at_telemetry_type_checker.dart';
import 'at_telemetry_log_record.dart';

// One OTLP ResourceLogs with a single ScopeLogs: the records one resource
// produced under one instrumentation scope
final class AtTelemetryResourceLogs {
  final Map<String, Object?> resourceAttributes;
  final String scopeName;
  final List<AtTelemetryLogRecord> records;

  AtTelemetryResourceLogs({
    Map<String, Object?> resourceAttributes = const <String, Object?>{},
    required this.scopeName,
    required List<AtTelemetryLogRecord> records,
  })  : resourceAttributes =
            Map<String, Object?>.unmodifiable(resourceAttributes),
        records = List<AtTelemetryLogRecord>.unmodifiable(records) {
    for (final MapEntry<String, Object?> entry in resourceAttributes.entries) {
      AtTelemetryTypeChecker.check(
        entry.value,
        'resourceAttributes.${entry.key}',
      );
    }
  }
}
