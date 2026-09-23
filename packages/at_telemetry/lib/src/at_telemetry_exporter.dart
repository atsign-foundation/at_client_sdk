import 'at_telemetry_event.dart';

abstract interface class AtTelemetryExporter {
  Future<void> export(AtTelemetryEvent event);

  Future<void> flush();

  Future<void> shutdown();
}
