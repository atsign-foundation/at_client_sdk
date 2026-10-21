import '../models/at_telemetry_log_record.dart';
import '../models/at_telemetry_resource.dart';

// Something a program uses to send telemetry to a collector. None of these
// Futures ever completes with an error, and flush and shutdown each return
// within a bounded time.
abstract interface class AtTelemetryLogRecordExporter {
  // Completes with true once the exporter has delivered the record, or taken
  // durable responsibility for it, and with false once it drops the record
  Future<bool> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  );

  // Sends what is queued now, and returns when that attempt ends. Records
  // that could not be sent stay queued for a later attempt.
  Future<void> flush();

  // A last flush, after which export only ever returns false
  Future<void> shutdown();
}
