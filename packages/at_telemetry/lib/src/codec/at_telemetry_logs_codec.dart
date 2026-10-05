import 'dart:typed_data';

import 'package:dartastic_opentelemetry/proto/collector/logs/v1/logs_service.pb.dart'
    as collector;
import 'package:dartastic_opentelemetry/proto/common/v1/common.pb.dart'
    as common;
import 'package:dartastic_opentelemetry/proto/logs/v1/logs.pb.dart' as logs;
import 'package:dartastic_opentelemetry/proto/resource/v1/resource.pb.dart'
    as otel_resource;
import 'package:fixnum/fixnum.dart';

import '../at_telemetry_log_record.dart';
import '../at_telemetry_resource.dart';
import '../at_telemetry_severity.dart';

final class AtTelemetryLogsCodec {
  static const String scopeName = 'at_telemetry';

  // The OTLP Protobuf types in dartastic_opentelemetry 0.11.0 have no
  // event_name field, so eventName travels as this attribute instead
  static const String eventNameAttribute = 'event.name';

  const AtTelemetryLogsCodec();

  // observedAt becomes every record's observedTimestamp, and the timestamp of
  // any record without one. It defaults to now.
  List<int> encodeExportRequest(
    Iterable<AtTelemetryLogRecord> records, {
    AtTelemetryResource? resource,
    DateTime? observedAt,
  }) {
    final DateTime observed = (observedAt ?? DateTime.now()).toUtc();
    final List<logs.LogRecord> logRecords = <logs.LogRecord>[
      for (final AtTelemetryLogRecord record in records)
        _encodeLogRecord(record, observed),
    ];
    if (logRecords.isEmpty) {
      throw ArgumentError.value(records, 'records', 'must not be empty');
    }

    return collector.ExportLogsServiceRequest(
      resourceLogs: <logs.ResourceLogs>[
        logs.ResourceLogs(
          resource: otel_resource.Resource(
            attributes: resource == null
                ? const <common.KeyValue>[]
                : _encodeAttributes(resource.attributes),
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

    final List<AtTelemetryLogRecord> records = <AtTelemetryLogRecord>[];
    for (final logs.ResourceLogs resourceLogs in request.resourceLogs) {
      final Map<String, Object?> resourceAttributes = resourceLogs.hasResource()
          ? _decodeAttributes(resourceLogs.resource.attributes)
          : const <String, Object?>{};

      for (final logs.ScopeLogs scopeLogs in resourceLogs.scopeLogs) {
        final Map<String, Object?> scopeAttributes = scopeLogs.hasScope()
            ? _decodeAttributes(scopeLogs.scope.attributes)
            : const <String, Object?>{};

        for (final logs.LogRecord logRecord in scopeLogs.logRecords) {
          records.add(
            _decodeLogRecord(
              logRecord,
              resourceAttributes: resourceAttributes,
              scopeAttributes: scopeAttributes,
            ),
          );
        }
      }
    }

    if (records.isEmpty) {
      throw const FormatException(
        'OTLP logs request must contain at least one log record',
      );
    }
    return List<AtTelemetryLogRecord>.unmodifiable(records);
  }

  List<int> encodeExportResponse() {
    return collector.ExportLogsServiceResponse().writeToBuffer();
  }

  logs.LogRecord _encodeLogRecord(
    AtTelemetryLogRecord record,
    DateTime observedAt,
  ) {
    final AtTelemetrySeverity? severity = record.severityNumber;
    return logs.LogRecord(
      timeUnixNano: _nanoseconds(record.timestamp ?? observedAt),
      observedTimeUnixNano: _nanoseconds(observedAt),
      severityNumber: severity == null
          ? null
          : logs.SeverityNumber.valueOf(severity.number),
      severityText: record.severityText,
      body: record.body == null ? null : _encodeValue(record.body),
      attributes: <common.KeyValue>[
        if (record.isEvent)
          common.KeyValue(
            key: eventNameAttribute,
            value: common.AnyValue(stringValue: record.eventName),
          ),
        // eventName wins over an event.name attribute on an Event
        for (final common.KeyValue attribute
            in _encodeAttributes(record.attributes))
          if (!record.isEvent || attribute.key != eventNameAttribute) attribute,
      ],
    );
  }

  AtTelemetryLogRecord _decodeLogRecord(
    logs.LogRecord logRecord, {
    required Map<String, Object?> resourceAttributes,
    required Map<String, Object?> scopeAttributes,
  }) {
    // Use timestamp when present, otherwise observedTimestamp, as the OTel
    // logs data model recommends for receivers with a single timestamp
    DateTime? timestamp;
    if (logRecord.timeUnixNano.toInt() > 0) {
      timestamp = _dateTime(logRecord.timeUnixNano);
    } else if (logRecord.observedTimeUnixNano.toInt() > 0) {
      timestamp = _dateTime(logRecord.observedTimeUnixNano);
    }

    AtTelemetrySeverity? severity;
    final int severityNumber = logRecord.severityNumber.value;
    if (severityNumber != 0) {
      severity = AtTelemetrySeverity.fromNumber(severityNumber);
      if (severity == null) {
        throw const FormatException(
          'OTLP log record severity number must be from 0 to 24',
        );
      }
    }

    final Map<String, Object?> attributes = <String, Object?>{
      ...resourceAttributes,
      ...scopeAttributes,
      ..._decodeAttributes(logRecord.attributes),
    };
    final Object? eventName = attributes.remove(eventNameAttribute);
    if (eventName != null && eventName is! String) {
      throw const FormatException(
        'OTLP $eventNameAttribute attribute must be a string',
      );
    }

    try {
      return AtTelemetryLogRecord(
        eventName: eventName as String?,
        body: logRecord.hasBody() ? _decodeValue(logRecord.body) : null,
        timestamp: timestamp,
        severityNumber: severity,
        severityText:
            logRecord.severityText.isEmpty ? null : logRecord.severityText,
        attributes: attributes,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid OTLP log record: ${error.message}');
    }
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

  Map<String, Object?> _decodeAttributes(Iterable<common.KeyValue> attributes) {
    return <String, Object?>{
      for (final common.KeyValue attribute in attributes)
        attribute.key: _decodeValue(attribute.value),
    };
  }

  // AtTelemetryLogRecord has already checked that value is an AnyValue
  common.AnyValue _encodeValue(Object? value) {
    return switch (value) {
      null => common.AnyValue(),
      final String value => common.AnyValue(stringValue: value),
      final bool value => common.AnyValue(boolValue: value),
      final int value => common.AnyValue(intValue: Int64(value)),
      final double value => common.AnyValue(doubleValue: value),
      // Uint8List is also a List<int>, so it must be matched before List
      final Uint8List value => common.AnyValue(bytesValue: value),
      final List<Object?> values => common.AnyValue(
          arrayValue: common.ArrayValue(
            values: values.map<common.AnyValue>(_encodeValue),
          ),
        ),
      final Map<String, Object?> values => common.AnyValue(
          kvlistValue: common.KeyValueList(values: _encodeAttributes(values)),
        ),
      _ => throw ArgumentError.value(value, 'value', 'is not an AnyValue'),
    };
  }

  Object? _decodeValue(common.AnyValue value) {
    return switch (value.whichValue()) {
      common.AnyValue_Value.stringValue => value.stringValue,
      common.AnyValue_Value.boolValue => value.boolValue,
      common.AnyValue_Value.intValue => value.intValue.toInt(),
      common.AnyValue_Value.doubleValue => value.doubleValue,
      common.AnyValue_Value.arrayValue => List<Object?>.unmodifiable(
          value.arrayValue.values.map<Object?>(_decodeValue),
        ),
      common.AnyValue_Value.kvlistValue => Map<String, Object?>.unmodifiable(
          _decodeAttributes(value.kvlistValue.values),
        ),
      common.AnyValue_Value.bytesValue => Uint8List.fromList(value.bytesValue),
      common.AnyValue_Value.notSet => null,
    };
  }

  Int64 _nanoseconds(DateTime time) =>
      Int64(time.microsecondsSinceEpoch) * 1000;

  DateTime _dateTime(Int64 nanoseconds) {
    try {
      return DateTime.fromMicrosecondsSinceEpoch(
        nanoseconds.toInt() ~/ 1000,
        isUtc: true,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid OTLP log record timestamp', error);
    }
  }
}
