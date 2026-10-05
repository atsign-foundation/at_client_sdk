import 'dart:convert';

import 'package:at_telemetry/at_telemetry.dart';

// Run with: dart run example/at_telemetry_example.dart
Future<void> main() async {
  final AtTelemetryLogRecord event = AtTelemetryLogRecord(
    name: 'atsign.app.started',
    timestamp: DateTime.now().toUtc(),
    attributes: const <String, Object?>{
      'app.version': '1.2.3',
      'app.debug': false,
      'app.retries': 2,
      'app.tags': <Object?>['cli', 'demo'],
      'app.device': <String, Object?>{'os': 'linux'},
    },
  );

  // Any exporter can be used behind the AtTelemetryExporter interface
  final AtTelemetryLogRecordExporter exporter = ConsoleExporter();
  await exporter.export(event);
  await exporter.flush();
  await exporter.shutdown();

  // Events round-trip through JSON
  final String json = jsonEncode(event.toJson());
  final AtTelemetryLogRecord fromJson = AtTelemetryLogRecord.fromJson(
    jsonDecode(json) as Map<String, Object?>,
  );
  print('JSON round trip: ${fromJson.name} at ${fromJson.timestamp}');
}

final class ConsoleExporter implements AtTelemetryLogRecordExporter {
  @override
  Future<void> export(AtTelemetryLogRecord event) async {
    print('Exported: ${jsonEncode(event.toJson())}');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}
