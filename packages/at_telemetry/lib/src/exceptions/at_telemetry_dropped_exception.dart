import '../models/at_telemetry_log_record.dart';

// An exporter gave up on a record without delivering it
final class AtTelemetryDroppedException implements Exception {
  final AtTelemetryLogRecord logRecord;

  const AtTelemetryDroppedException(this.logRecord);

  @override
  String toString() {
    final String name = logRecord.eventName ?? 'log record';
    return 'AtTelemetryDroppedException: $name was not delivered';
  }
}
