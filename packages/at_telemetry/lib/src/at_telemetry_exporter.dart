import 'at_telemetry_event.dart';

// An exporter is something that a client uses to emit telemetry to a collector
abstract interface class AtTelemetryExporter {
  Future<void> export(AtTelemetryEvent event);
  Future<void> flush();
  Future<void> shutdown();
}
