import 'dart:convert';

import 'package:at_telemetry/at_telemetry.dart';

// Run with: dart run example/at_telemetry_example.dart
Future<void> main() async {
  final AtTelemetry telemetry = AtTelemetry(
    serviceName: 'my_app',
    resourceAttributes: const <String, Object?>{'app.version': '1.2.3'},
    exporter: ConsoleExporter(),
    onError: (Object error, StackTrace _) => print('Telemetry failed: $error'),
  );

  telemetry.event(
    'atsign.app.started',
    attributes: const <String, Object?>{
      'app.debug': false,
      'app.retries': 2,
      'app.tags': <Object?>['cli', 'demo'],
      'app.device': <String, Object?>{'os': 'linux'},
    },
  );
  telemetry.log('Reconnecting to the atServer',
      severity: AtTelemetrySeverity.warn);

  await telemetry.shutdown();
}

final class ConsoleExporter implements AtTelemetryLogRecordExporter {
  @override
  Future<void> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) async {
    print('Exported from ${resource.serviceName}: '
        '${jsonEncode(logRecord.toJson())}');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}
