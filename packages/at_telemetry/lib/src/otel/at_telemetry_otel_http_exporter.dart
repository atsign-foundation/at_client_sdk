// ignore_for_file: prefer_initializing_formals

import 'package:at_telemetry/src/at_telemetry_event.dart';
import 'package:at_telemetry/src/at_telemetry_exporter.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

final class AtTelemetryExporterOtelHttp implements AtTelemetryExporter {
  final OTelLogger _logger;

  AtTelemetryExporterOtelHttp._({
    required OTelLogger logger,
  }) : _logger = logger;

  static Future<AtTelemetryExporterOtelHttp> create({
    required Uri endpoint,
    required String serviceName,
  }) async {
    await OTel.initialize(
      endpoint: endpoint.toString(),
      serviceName: serviceName,
      enableMetrics: false,
      enableLogs: true,
    );

    return AtTelemetryExporterOtelHttp._(
      logger: OTel.logger('at_telemetry'),
    );
  }

  @override
  Future<void> export(AtTelemetryEvent event) async {
    // 1. Remove null value entries
    final Map<String, Object> nonNullValueAttributes = {};

    for(final MapEntry<String, Object?> entry in event.attributes.entries) {
      if(entry.value != null) {
        nonNullValueAttributes[entry.key] = entry.value!;
      }
    }

    // send the event to the logger provider
    // note: call flush() to immediately send
    _logger.emit(
      timeStamp: event.timestamp,
      severityNumber: Severity.INFO,
      body: event.name,
      eventName: event.name,
      attributes: OTel.attributesFromMap(nonNullValueAttributes),
    );
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
