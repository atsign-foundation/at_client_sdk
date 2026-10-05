import '../at_telemetry_log_record.dart';
import '../at_telemetry_resource.dart';

// An exporter is something that a client uses to emit telemetry to a
// collector. The Future from export fails when the record is not delivered.
// flush waits for every queued record and never throws.
abstract interface class AtTelemetryLogRecordExporter {
  Future<void> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  );
  Future<void> flush();
  Future<void> shutdown();
}
