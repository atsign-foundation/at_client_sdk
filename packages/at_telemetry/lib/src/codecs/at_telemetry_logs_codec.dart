import 'dart:convert';
import 'dart:typed_data';

import '../models/at_telemetry_log_record.dart';
import '../models/at_telemetry_resource.dart';
import '../models/at_telemetry_resource_logs.dart';
import '../models/at_telemetry_severity.dart';

// Encodes and decodes OTLP/JSON ExportLogsServiceRequest bodies, built
// directly from maps. It follows the OTLP JSON Protobuf encoding:
// lowerCamelCase field names, 64-bit integers as decimal strings, enums as
// integers and bytes as base64. Decoding ignores fields it does not know.
final class AtTelemetryLogsCodec {
  static const String contentType = 'application/json';
  static const String scopeName = 'at_telemetry';
  static final RegExp _unsignedPattern = RegExp(r'^[0-9]{1,20}$');
  static final RegExp _signedPattern = RegExp(r'^-?[0-9]{1,19}$');
  static final RegExp _zeroPattern = RegExp(r'^0+$');

  const AtTelemetryLogsCodec();

  String encodeExportRequest(
    Iterable<AtTelemetryLogRecord> records, {
    AtTelemetryResource? resource,
    DateTime? observedAt,
  }) {
    return encode(
      <AtTelemetryResourceLogs>[
        AtTelemetryResourceLogs(
          resourceAttributes: resource?.attributes ?? const <String, Object?>{},
          scopeName: scopeName,
          records: records.toList(),
        ),
      ],
      observedAt: observedAt,
    );
  }

  // observedAt becomes the observedTimestamp of every record without one,
  // and the timestamp of every record without either. It defaults to now.
  String encode(
    Iterable<AtTelemetryResourceLogs> resourceLogs, {
    DateTime? observedAt,
  }) {
    final DateTime observed = (observedAt ?? DateTime.now()).toUtc();
    if (observed.isBefore(AtTelemetryLogRecord.minTimestamp) ||
        observed.isAfter(AtTelemetryLogRecord.maxTimestamp)) {
      throw ArgumentError.value(observedAt, 'observedAt', 'is out of range');
    }
    final List<Map<String, Object?>> encoded = <Map<String, Object?>>[
      for (final AtTelemetryResourceLogs logs in resourceLogs)
        if (logs.records.isNotEmpty) _encodeResourceLogs(logs, observed),
    ];
    if (encoded.isEmpty) {
      throw ArgumentError.value(
        resourceLogs,
        'resourceLogs',
        'must contain at least one log record',
      );
    }
    return jsonEncode(<String, Object?>{'resourceLogs': encoded});
  }

  List<AtTelemetryResourceLogs> decode(String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (error) {
      throw FormatException('Invalid OTLP/JSON logs payload', error.message);
    }

    final List<AtTelemetryResourceLogs> result = <AtTelemetryResourceLogs>[];
    final Map<String, Object?> request = _object(decoded, 'request');
    for (final Object? item in _list(request['resourceLogs'], 'resourceLogs')) {
      final Map<String, Object?> resourceLogs = _object(item, 'resourceLogs');
      final Object? resource = resourceLogs['resource'];
      final Map<String, Object?> resourceAttributes = resource == null
          ? const <String, Object?>{}
          : _decodeAttributes(_object(resource, 'resource')['attributes']);

      for (final Object? scopeItem
          in _list(resourceLogs['scopeLogs'], 'scopeLogs')) {
        final Map<String, Object?> scopeLogs = _object(scopeItem, 'scopeLogs');
        final Object? scope = scopeLogs['scope'];
        final Object? name =
            scope == null ? null : _object(scope, 'scope')['name'];
        if (name != null && name is! String) {
          throw const FormatException('scope.name must be a string');
        }
        final List<AtTelemetryLogRecord> records = <AtTelemetryLogRecord>[
          for (final Object? record
              in _list(scopeLogs['logRecords'], 'logRecords'))
            _decodeLogRecord(_object(record, 'logRecords')),
        ];
        if (records.isEmpty) {
          continue;
        }
        try {
          result.add(AtTelemetryResourceLogs(
            resourceAttributes: resourceAttributes,
            scopeName: (name as String?) ?? '',
            records: records,
          ));
        } on ArgumentError catch (error) {
          throw FormatException('Invalid OTLP resource: ${error.message}');
        }
      }
    }

    if (result.isEmpty) {
      throw const FormatException(
        'OTLP logs request must contain at least one log record',
      );
    }
    return List<AtTelemetryResourceLogs>.unmodifiable(result);
  }

  // The OTLP/JSON ExportLogsServiceResponse for a fully accepted request
  String encodeExportResponse() => '{}';

  Map<String, Object?> _encodeResourceLogs(
    AtTelemetryResourceLogs logs,
    DateTime observedAt,
  ) {
    return <String, Object?>{
      'resource': <String, Object?>{
        'attributes': _encodeAttributes(logs.resourceAttributes),
      },
      'scopeLogs': <Map<String, Object?>>[
        <String, Object?>{
          'scope': <String, Object?>{'name': logs.scopeName},
          'logRecords': <Map<String, Object?>>[
            for (final AtTelemetryLogRecord record in logs.records)
              _encodeLogRecord(record, observedAt),
          ],
        },
      ],
    };
  }

  Map<String, Object?> _encodeLogRecord(
    AtTelemetryLogRecord record,
    DateTime observedAt,
  ) {
    final DateTime observed = record.observedTimestamp ?? observedAt;
    final AtTelemetrySeverity? severity = record.severityNumber;
    return <String, Object?>{
      'timeUnixNano': _nanoseconds(record.timestamp ?? observed),
      'observedTimeUnixNano': _nanoseconds(observed),
      if (severity != null) 'severityNumber': severity.number,
      if (record.severityText != null) 'severityText': record.severityText,
      if (record.body != null) 'body': _encodeValue(record.body),
      'attributes': _encodeAttributes(record.attributes),
      if (record.isEvent) 'eventName': record.eventName,
    };
  }

  AtTelemetryLogRecord _decodeLogRecord(Map<String, Object?> json) {
    final Object? severityNumber = json['severityNumber'];
    AtTelemetrySeverity? severity;
    if (severityNumber != null && severityNumber != 0) {
      if (severityNumber is! int) {
        throw const FormatException('severityNumber must be an integer');
      }
      severity = AtTelemetrySeverity.fromNumber(severityNumber);
      if (severity == null) {
        throw const FormatException('severityNumber must be from 0 to 24');
      }
    }

    final Object? severityText = json['severityText'];
    if (severityText != null && severityText is! String) {
      throw const FormatException('severityText must be a string');
    }
    final Object? eventName = json['eventName'];
    if (eventName != null && eventName is! String) {
      throw const FormatException('eventName must be a string');
    }
    final String? name = eventName as String?;
    final String? text = severityText as String?;

    try {
      return AtTelemetryLogRecord(
        eventName: name == null || name.isEmpty ? null : name,
        body: json['body'] == null ? null : _decodeValue(json['body'], 'body'),
        timestamp: _decodeTime(json['timeUnixNano'], 'timeUnixNano'),
        observedTimestamp: _decodeTime(
          json['observedTimeUnixNano'],
          'observedTimeUnixNano',
        ),
        severityNumber: severity,
        severityText: text == null || text.isEmpty ? null : text,
        attributes: _decodeAttributes(json['attributes']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid OTLP log record: ${error.message}');
    }
  }

  List<Map<String, Object?>> _encodeAttributes(
    Map<String, Object?> attributes,
  ) {
    return <Map<String, Object?>>[
      for (final MapEntry<String, Object?> entry in attributes.entries)
        if (entry.value != null)
          <String, Object?>{
            'key': entry.key,
            'value': _encodeValue(entry.value),
          },
    ];
  }

  Map<String, Object?> _decodeAttributes(Object? json) {
    final Map<String, Object?> attributes = <String, Object?>{};
    for (final Object? item in _list(json, 'attributes')) {
      final Map<String, Object?> keyValue = _object(item, 'attributes');
      final Object? key = keyValue['key'];
      if (key is! String) {
        throw const FormatException('attribute key must be a string');
      }
      final Object? value = keyValue['value'];
      attributes[key] = value == null ? null : _decodeValue(value, key);
    }
    return attributes;
  }

  // The record has already checked that value is an AnyValue
  Map<String, Object?> _encodeValue(Object? value) {
    return switch (value) {
      null => const <String, Object?>{},
      final String value => <String, Object?>{'stringValue': value},
      final bool value => <String, Object?>{'boolValue': value},
      final int value => <String, Object?>{'intValue': '$value'},
      final double value => <String, Object?>{'doubleValue': value},
      // Uint8List is also a List<int>, so it must be matched before List
      final Uint8List value => <String, Object?>{
          'bytesValue': base64Encode(value),
        },
      final List<Object?> values => <String, Object?>{
          'arrayValue': <String, Object?>{
            'values': <Map<String, Object?>>[
              for (final Object? item in values) _encodeValue(item),
            ],
          },
        },
      final Map<String, Object?> values => <String, Object?>{
          'kvlistValue': <String, Object?>{
            'values': _encodeAttributes(values),
          },
        },
      _ => throw ArgumentError.value(value, 'value', 'is not an AnyValue'),
    };
  }

  Object? _decodeValue(Object? json, String path) {
    final Map<String, Object?> value = _object(json, path);
    if (value.containsKey('stringValue')) {
      final Object? string = value['stringValue'];
      if (string is! String) {
        throw FormatException('$path.stringValue must be a string');
      }
      return string;
    }
    if (value.containsKey('boolValue')) {
      final Object? boolean = value['boolValue'];
      if (boolean is! bool) {
        throw FormatException('$path.boolValue must be a boolean');
      }
      return boolean;
    }
    if (value.containsKey('intValue')) {
      final Object? integer = value['intValue'];
      if (integer is int) {
        return integer;
      }
      if (integer is! String || !_signedPattern.hasMatch(integer)) {
        throw FormatException('$path.intValue must be a 64-bit integer');
      }
      final int? parsed = int.tryParse(integer);
      if (parsed == null) {
        throw FormatException('$path.intValue must be a 64-bit integer');
      }
      return parsed;
    }
    if (value.containsKey('doubleValue')) {
      final Object? number = value['doubleValue'];
      if (number is! num || !number.isFinite) {
        throw FormatException('$path.doubleValue must be a finite number');
      }
      return number.toDouble();
    }
    if (value.containsKey('bytesValue')) {
      final Object? bytes = value['bytesValue'];
      if (bytes is! String) {
        throw FormatException('$path.bytesValue must be base64');
      }
      try {
        return base64Decode(bytes);
      } on FormatException {
        throw FormatException('$path.bytesValue must be base64');
      }
    }
    if (value.containsKey('arrayValue')) {
      final Map<String, Object?> array =
          _object(value['arrayValue'], '$path.arrayValue');
      final List<Object?> items = _list(array['values'], '$path.arrayValue');
      return List<Object?>.unmodifiable(<Object?>[
        for (int index = 0; index < items.length; index++)
          _decodeValue(items[index], '$path[$index]'),
      ]);
    }
    if (value.containsKey('kvlistValue')) {
      final Map<String, Object?> kvlist =
          _object(value['kvlistValue'], '$path.kvlistValue');
      return Map<String, Object?>.unmodifiable(
        _decodeAttributes(kvlist['values']),
      );
    }
    return null;
  }

  // Built as text so that neither JavaScript's 53-bit numbers nor a signed
  // 64-bit nanosecond count limits the range
  String _nanoseconds(DateTime time) {
    final int microseconds = time.microsecondsSinceEpoch;
    return microseconds == 0 ? '0' : '${microseconds}000';
  }

  DateTime? _decodeTime(Object? json, String path) {
    if (json == null) {
      return null;
    }
    final String text = json is int ? '$json' : (json is String ? json : '');
    if (!_unsignedPattern.hasMatch(text)) {
      throw FormatException('$path must be unsigned 64-bit nanoseconds');
    }
    // Zero means the time is unknown
    if (_zeroPattern.hasMatch(text)) {
      return null;
    }
    final int microseconds =
        text.length > 3 ? int.parse(text.substring(0, text.length - 3)) : 0;
    return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
  }

  Map<String, Object?> _object(Object? json, String path) {
    if (json is! Map<String, Object?>) {
      throw FormatException('$path must be a JSON object');
    }
    return json;
  }

  // Proto3 JSON leaves empty repeated fields out
  List<Object?> _list(Object? json, String path) {
    if (json == null) {
      return const <Object?>[];
    }
    if (json is! List<Object?>) {
      throw FormatException('$path must be a JSON array');
    }
    return json;
  }
}
