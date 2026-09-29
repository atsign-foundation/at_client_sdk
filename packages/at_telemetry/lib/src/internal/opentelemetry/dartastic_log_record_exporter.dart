// ignore_for_file: prefer_initializing_formals

import 'package:at_telemetry/src/models/logs/at_telemetry_log_record.dart';
import 'package:at_telemetry/src/exporters/at_telemetry_log_record_exporter.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

final class DartasticLogRecordExporter
    implements AtTelemetryLogRecordExporter {
  final OTelLogger _logger;

  DartasticLogRecordExporter._({
    required OTelLogger logger,
  }) : _logger = logger;

  static Future<DartasticLogRecordExporter> create({
    required Uri endpoint,
    required String serviceName,
    bool detectPlatformResources = true,
  }) async {
    final OtlpHttpLogRecordExporter logRecordExporter =
        OtlpHttpLogRecordExporter(
      OtlpHttpLogRecordExporterConfig(
        endpoint: endpoint.toString(),
        protocol: OtlpHttpProtocol.httpProtobuf,
        headers: const <String, String>{},
      ),
    );

    await OTel.initialize(
      endpoint: endpoint.toString(),
      serviceName: serviceName,
      enableMetrics: false,
      enableLogs: true,
      logRecordExporter: logRecordExporter,
      detectPlatformResources: detectPlatformResources,
    );

    return DartasticLogRecordExporter._(
      logger: OTel.logger('at_telemetry'),
    );
  }

  @override
  Future<void> export(AtTelemetryLogRecord event) {
    final Map<String, Object> attributes = <String, Object>{};

    for (final MapEntry<String, Object?> entry in event.attributes.entries) {
      final Object? value = entry.value;
      if (value != null) {
        attributes[entry.key] = value;
      }
    }

    _logger.emit(
      timeStamp: event.timestamp,
      severityNumber: Severity.INFO,
      body: event.name,
      eventName: event.name,
      attributes: OTel.attributesFromMap(attributes),
    );

    return Future<void>.value();
  }

  @override
  Future<void> flush() {
    return OTel.loggerProvider().forceFlush();
  }

  @override
  Future<void> shutdown() {
    return OTel.shutdown();
  }
}
