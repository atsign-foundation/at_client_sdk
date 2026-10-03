import '../models/logs/at_telemetry_log_record.dart';

// An exporter is something that a client uses to emit telemetry to a collector
abstract interface class AtTelemetryLogRecordExporter {
  Future<void> export(AtTelemetryLogRecord logRecord);
  Future<void> flush();
  Future<void> shutdown();
}
