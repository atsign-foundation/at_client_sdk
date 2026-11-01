import 'package:at_telemetry/at_telemetry.dart';

// Run with: dart run example/at_telemetry_example.dart
Future<void> main() async {
  final AtTelemetry telemetry = AtTelemetry(
    serviceName: 'my_app',
    resourceAttributes: AtTelemetryResource.app(serviceVersion: '1.2.3'),
    exporter: ConsoleExporter(),
    onError: (Object error, StackTrace _) => print('Telemetry failed: $error'),
  );

  telemetry.event(
    'my_app.session.started',
    attributes: const <String, Object?>{
      'my_app.debug': false,
      'my_app.retries': 2,
      'my_app.tags': <Object?>['cli', 'demo'],
      'my_app.device': <String, Object?>{'os': 'linux'},
    },
  );
  telemetry.log('Reconnecting to the atServer',
      severity: AtTelemetrySeverity.warn);

  await telemetry.shutdown();
}

final class ConsoleExporter implements AtTelemetryLogRecordExporter {
  @override
  Future<bool> export(
    AtTelemetryLogRecord logRecord,
    AtTelemetryResource resource,
  ) async {
    print(const AtTelemetryLogsCodec().encodeExportRequest(
      <AtTelemetryLogRecord>[logRecord],
      resource: resource,
    ));
    return true;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}
