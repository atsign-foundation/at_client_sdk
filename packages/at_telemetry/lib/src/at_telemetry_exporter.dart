import 'package:at_telemetry/at_telemetry.dart';

abstract interface class AtTelemetryExporter {
  Future<void> export(AtTelemetryEvent event);
  Future<void> flush();
  Future<void> shutdown();
}
