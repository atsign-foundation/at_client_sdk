// ignore_for_file: prefer_initializing_formals

import 'package:at_telemetry/src/at_telemetry_event.dart';
import 'package:at_telemetry/src/at_telemetry_exporter.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

final class AtTelemetryExporterOtlpHttp implements AtTelemetryExporter {
  final OTelLogger _logger;

  AtTelemetryExporterOtlpHttp._({
    required OTelLogger logger,
  }) : _logger = logger;

  static Future<AtTelemetryExporterOtlpHttp> create({
    required Uri endpoint,
    required String serviceName,
  }) async {
    await OTel.initialize(
      endpoint: endpoint.toString(),
      serviceName: serviceName,
      enableMetrics: false,
      enableLogs: true,
    );

    return AtTelemetryExporterOtlpHttp._(
      logger: OTel.logger('at_telemetry'),
    );
  }

  @override
  Future<void> export(AtTelemetryEvent event) async {
    Map<String, Object> nonNullValueAttributes = {};

    for(final MapEntry<String, Object?> entry in event.attributes.entries) {
      if(entry.value != null) {
        nonNullValueAttributes[entry.key] = entry.value!;
      }
    }

    _logger.emit(
      timeStamp: event.timestamp,
      severityNumber: Severity.INFO,
      body: event.name,
      eventName: event.name,
      attributes: OTel.attributesFromMap(nonNullValueAttributes),
    );

    await OTel.loggerProvider().forceFlush();
  }
}
