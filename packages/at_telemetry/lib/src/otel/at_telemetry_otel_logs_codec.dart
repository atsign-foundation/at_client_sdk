import 'dart:convert';

import 'package:at_telemetry/src/at_telemetry_event.dart';
import 'package:dartastic_opentelemetry/proto/collector/logs/v1/logs_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/logs/v1/logs.pb.dart' as logs;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as resource;
import 'package:fixnum/fixnum.dart';

final class AtTelemetryOtelLogsCodec {
  static const String scopeName = 'at_telemetry';

  const AtTelemetryOtelLogsCodec();

  List<int> encodeExportRequest(
    Iterable<AtTelemetryEvent> events, {
    String? serviceName,
  }) {
    final List<logs.LogRecord> logRecords = <logs.LogRecord>[
      for (final AtTelemetryEvent event in events) _encodeLogRecord(event),
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

  List<AtTelemetryEvent> decodeExportRequest(List<int> payload) {
    final collector.ExportLogsServiceRequest request;
    try {
      request = collector.ExportLogsServiceRequest.fromBuffer(payload);
    } on Object catch (error) {
      throw FormatException('Invalid OTLP logs Protobuf payload', error);
    }

    final List<AtTelemetryEvent> events = <AtTelemetryEvent>[];
    for (final logs.ResourceLogs resourceLogs in request.resourceLogs) {
      final Map<String, Object?> resourceAttributes = resourceLogs.hasResource()
          ? _decodeAttributes(resourceLogs.resource.attributes)
          : const <String, Object?>{};

      for (final logs.ScopeLogs scopeLogs in resourceLogs.scopeLogs) {
        final Map<String, Object?> scopeAttributes = scopeLogs.hasScope()
            ? _decodeAttributes(scopeLogs.scope.attributes)
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
    return List<AtTelemetryEvent>.unmodifiable(events);
  }

  List<int> encodeExportResponse() {
    return collector.ExportLogsServiceResponse().writeToBuffer();
  }

  logs.LogRecord _encodeLogRecord(AtTelemetryEvent event) {
    if (event.name.trim().isEmpty) {
      throw ArgumentError.value(event.name, 'event.name', 'must not be empty');
    }

    return logs.LogRecord(
      timeUnixNano: Int64(event.timestamp.microsecondsSinceEpoch) * 1000,
      severityNumber: logs.SeverityNumber.SEVERITY_NUMBER_INFO,
      body: common.AnyValue(stringValue: event.name),
      attributes: _encodeAttributes(event.attributes),
    );
  }

  List<common.KeyValue> _encodeAttributes(Map<String, Object?> attributes) {
    return <common.KeyValue>[
      for (final MapEntry<String, Object?> entry in attributes.entries)
        if (entry.value != null)
          common.KeyValue(
            key: entry.key,
            value: _encodeValue(entry.value),
          ),
    ];
  }

  common.AnyValue _encodeValue(Object? value) {
    return switch (value) {
      final String value => common.AnyValue(stringValue: value),
      final bool value => common.AnyValue(boolValue: value),
      final int value => common.AnyValue(intValue: Int64(value)),
      final double value => common.AnyValue(doubleValue: _decodeDouble(value)),
      final List<Object?> values => common.AnyValue(
          arrayValue: common.ArrayValue(
            values: values.map<common.AnyValue>(_encodeValue),
          ),
        ),
      final Map<String, Object?> values => common.AnyValue(
          kvlistValue: common.KeyValueList(values: _encodeAttributes(values)),
        ),
      _ => throw ArgumentError.value(
          value,
          'attributes',
          'values must be String, bool, int, double, List, or Map',
        ),
    };
  }

  AtTelemetryEvent _decodeLogRecord(
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
      ..._decodeAttributes(logRecord.attributes),
    };
    return AtTelemetryEvent(
      name: logRecord.body.stringValue,
      timestamp: timestamp,
      attributes: Map<String, Object?>.unmodifiable(attributes),
    );
  }

  Map<String, Object?> _decodeAttributes(
    Iterable<common.KeyValue> attributes,
  ) {
    return <String, Object?>{
      for (final common.KeyValue attribute in attributes)
        attribute.key: _decodeValue(attribute.value),
    };
  }

  Object? _decodeValue(common.AnyValue value) {
    return switch (value.whichValue()) {
      common.AnyValue_Value.stringValue => value.stringValue,
      common.AnyValue_Value.boolValue => value.boolValue,
      common.AnyValue_Value.intValue => value.intValue.toInt(),
      common.AnyValue_Value.doubleValue => _decodeDouble(value.doubleValue),
      common.AnyValue_Value.arrayValue => List<Object?>.unmodifiable(
          value.arrayValue.values.map<Object?>(_decodeValue),
        ),
      common.AnyValue_Value.kvlistValue => Map<String, Object?>.unmodifiable(
          _decodeAttributes(value.kvlistValue.values),
        ),
      common.AnyValue_Value.bytesValue => base64Encode(value.bytesValue),
      common.AnyValue_Value.notSet => throw const FormatException(
          'OTLP attribute value must be set',
        ),
    };
  }

  double _decodeDouble(double value) {
    if (!value.isFinite) {
      throw const FormatException(
        'OTLP double attributes must be finite',
      );
    }
    return value;
  }
}
