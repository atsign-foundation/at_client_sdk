import 'package:at_telemetry/src/models/logs/at_telemetry_log_record.dart';
import 'package:at_telemetry/src/internal/opentelemetry/dartastic_attributes_codec.dart';
import 'package:dartastic_opentelemetry/proto/collector/logs/v1/logs_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/logs/v1/logs.pb.dart' as logs;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as resource;
import 'package:fixnum/fixnum.dart';

final class DartasticLogsCodec {
  static const String scopeName = 'at_telemetry';
  static const DartasticAttributesCodec _attributes =
      DartasticAttributesCodec();

  const DartasticLogsCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetryLogRecord> events, {
    String? serviceName,
  }) {
    final List<logs.LogRecord> logRecords = <logs.LogRecord>[
      for (final AtTelemetryLogRecord event in events) _encodeLogRecord(event),
    ];
    if (logRecords.isEmpty) {
      throw ArgumentError.value(events, 'events', 'must not be empty');
    }

    return collector.ExportLogsServiceRequest(
      resourceLogs: <logs.ResourceLogs>[
        logs.ResourceLogs(
          resource: resource.Resource(
            attributes: serviceName == null
                ? const <common.KeyValue>[]
                : <common.KeyValue>[
                    common.KeyValue(
                      key: 'service.name',
                      value: common.AnyValue(stringValue: serviceName),
                    ),
                  ],
          ),
          scopeLogs: <logs.ScopeLogs>[
            logs.ScopeLogs(
              scope: common.InstrumentationScope(name: scopeName),
              logRecords: logRecords,
            ),
          ],
        ),
      ],
    ).writeToBuffer();
  }

  List<AtTelemetryLogRecord> decodeExportRequest(List<int> payload) {
    final collector.ExportLogsServiceRequest request;
    try {
      request = collector.ExportLogsServiceRequest.fromBuffer(payload);
    } on Object catch (error) {
      throw FormatException('Invalid OTLP logs Protobuf payload', error);
    }

    final List<AtTelemetryLogRecord> events = <AtTelemetryLogRecord>[];
    for (final logs.ResourceLogs resourceLogs in request.resourceLogs) {
      final Map<String, Object?> resourceAttributes = resourceLogs.hasResource()
          ? _attributes.decode(resourceLogs.resource.attributes)
          : const <String, Object?>{};

      for (final logs.ScopeLogs scopeLogs in resourceLogs.scopeLogs) {
        final Map<String, Object?> scopeAttributes = scopeLogs.hasScope()
            ? _attributes.decode(scopeLogs.scope.attributes)
            : const <String, Object?>{};

        for (final logs.LogRecord logRecord in scopeLogs.logRecords) {
          events.add(
            _decodeLogRecord(
              logRecord,
              resourceAttributes: resourceAttributes,
              scopeAttributes: scopeAttributes,
            ),
          );
        }
      }
    }

    if (events.isEmpty) {
      throw const FormatException(
        'OTLP logs request must contain at least one log record',
      );
    }
    return List<AtTelemetryLogRecord>.unmodifiable(events);
  }

  List<int> encodeExportResponse() {
    return collector.ExportLogsServiceResponse().writeToBuffer();
  }

  logs.LogRecord _encodeLogRecord(AtTelemetryLogRecord event) {
    if (event.name.trim().isEmpty) {
      throw ArgumentError.value(event.name, 'event.name', 'must not be empty');
    }

    return logs.LogRecord(
      timeUnixNano: Int64(event.timestamp.microsecondsSinceEpoch) * 1000,
      severityNumber: logs.SeverityNumber.SEVERITY_NUMBER_INFO,
      body: common.AnyValue(stringValue: event.name),
      attributes: _attributes.encode(event.attributes),
    );
  }

  AtTelemetryLogRecord _decodeLogRecord(
    logs.LogRecord logRecord, {
    required Map<String, Object?> resourceAttributes,
    required Map<String, Object?> scopeAttributes,
  }) {
    if (!logRecord.hasBody() ||
        logRecord.body.whichValue() != common.AnyValue_Value.stringValue ||
        logRecord.body.stringValue.trim().isEmpty) {
      throw const FormatException(
        'OTLP log record body must be a non-empty string event name',
      );
    }

    final int timestampNanoseconds;
    if (logRecord.timeUnixNano.toInt() > 0) {
      timestampNanoseconds = logRecord.timeUnixNano.toInt();
    } else if (logRecord.observedTimeUnixNano.toInt() > 0) {
      timestampNanoseconds = logRecord.observedTimeUnixNano.toInt();
    } else {
      throw const FormatException(
        'OTLP log record must contain a timestamp',
      );
    }

    final DateTime timestamp;
    try {
      timestamp = DateTime.fromMicrosecondsSinceEpoch(
        timestampNanoseconds ~/ 1000,
        isUtc: true,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid OTLP log record timestamp', error);
    }

    final Map<String, Object?> attributes = <String, Object?>{
      ...resourceAttributes,
      ...scopeAttributes,
      ..._attributes.decode(logRecord.attributes),
    };
    return AtTelemetryLogRecord(
      name: logRecord.body.stringValue,
      timestamp: timestamp,
      attributes: Map<String, Object?>.unmodifiable(attributes),
    );
  }
}
