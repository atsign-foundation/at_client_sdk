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
    String? apiKey,
  }) async {
    if (apiKey != null && (apiKey.isEmpty || apiKey.contains(RegExp(r'\s')))) {
      throw ArgumentError.value(
        apiKey.isEmpty ? apiKey : '<redacted>',
        'apiKey',
        'must be non-empty and contain no whitespace',
      );
    }

    final OtlpHttpLogRecordExporter logRecordExporter =
        OtlpHttpLogRecordExporter(
      OtlpHttpLogRecordExporterConfig(
        endpoint: endpoint.toString(),
        protocol: OtlpHttpProtocol.httpProtobuf,
        headers: apiKey == null
            ? const <String, String>{}
            : <String, String>{'authorization': 'Bearer $apiKey'},
      ),
    );

    await OTel.initialize(
      endpoint: endpoint.toString(),
      serviceName: serviceName,
      enableMetrics: false,
      enableLogs: true,
      logRecordExporter: logRecordExporter,
    );

    return AtTelemetryExporterOtelHttp._(
      logger: OTel.logger('at_telemetry'),
    );
  }

  @override
  Future<void> export(AtTelemetryEvent event) {
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
