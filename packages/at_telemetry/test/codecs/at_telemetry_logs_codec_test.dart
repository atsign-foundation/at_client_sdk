import 'dart:convert';
import 'dart:typed_data';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

// Pinned with raw OTLP/JSON literals rather than generated classes, so a
// change to the encoding shows up as a diff against the specification's
// shape: lowerCamelCase names, 64-bit integers as decimal strings, enums as
// integers and bytes as base64.
void main() {
  const AtTelemetryLogsCodec codec = AtTelemetryLogsCodec();

  group('AtTelemetryLogsCodec.encodeExportRequest', () {
    test('writes every field as the OTLP JSON encoding specifies', () {
      final String encoded = codec.encodeExportRequest(
        <AtTelemetryLogRecord>[
          AtTelemetryLogRecord(
            eventName: 'login',
            body: 'hello',
            timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7),
            severityNumber: AtTelemetrySeverity.warn,
            severityText: 'WARN',
            attributes: <String, Object?>{
              's': 'x',
              'b': true,
              'i': 42,
              'd': 1.5,
              'bytes': Uint8List.fromList(<int>[1, 2, 3]),
              'list': <Object?>[1, 'a', null],
              'map': <String, Object?>{'k': 'v', 'n': null},
              'skipped': null,
            },
          ),
        ],
        resource: AtTelemetryResource(
          serviceName: 'svc',
          attributes: const <String, Object?>{'atsign.atserver.id': '@alice'},
        ),
        observedAt: DateTime.utc(2024, 1, 2, 3, 4, 6),
      );

      expect(jsonDecode(encoded), jsonDecode('''
{"resourceLogs":[{
  "resource":{"attributes":[
    {"key":"atsign.atserver.id","value":{"stringValue":"@alice"}},
    {"key":"service.name","value":{"stringValue":"svc"}}]},
  "scopeLogs":[{
    "scope":{"name":"at_telemetry"},
    "logRecords":[{
      "timeUnixNano":"1704164645006007000",
      "observedTimeUnixNano":"1704164646000000000",
      "severityNumber":13,
      "severityText":"WARN",
      "body":{"stringValue":"hello"},
      "attributes":[
        {"key":"s","value":{"stringValue":"x"}},
        {"key":"b","value":{"boolValue":true}},
        {"key":"i","value":{"intValue":"42"}},
        {"key":"d","value":{"doubleValue":1.5}},
        {"key":"bytes","value":{"bytesValue":"AQID"}},
        {"key":"list","value":{"arrayValue":{"values":[
          {"intValue":"1"},{"stringValue":"a"},{}]}}},
        {"key":"map","value":{"kvlistValue":{"values":[
          {"key":"k","value":{"stringValue":"v"}}]}}}],
      "eventName":"login"}]}]}]}
'''));
    });

    test('a plain log has no eventName, and omits unset fields', () {
      final String encoded = codec.encodeExportRequest(
        <AtTelemetryLogRecord>[AtTelemetryLogRecord(body: 'line')],
        observedAt: DateTime.utc(2024, 1, 2, 3, 4, 6),
      );

      expect(jsonDecode(encoded), jsonDecode('''
{"resourceLogs":[{
  "resource":{"attributes":[]},
  "scopeLogs":[{
    "scope":{"name":"at_telemetry"},
    "logRecords":[{
      "timeUnixNano":"1704164646000000000",
      "observedTimeUnixNano":"1704164646000000000",
      "body":{"stringValue":"line"},
      "attributes":[]}]}]}]}
'''));
    });

    test('keeps a record\'s own observedTimestamp', () {
      final String encoded = codec.encodeExportRequest(
        <AtTelemetryLogRecord>[
          AtTelemetryLogRecord(
            body: 'line',
            observedTimestamp: DateTime.utc(2024, 1, 2, 3, 4, 5),
          ),
        ],
        observedAt: DateTime.utc(2024, 1, 2, 3, 4, 6),
      );

      final Map<String, Object?> record = _onlyRecord(encoded);
      expect(record['observedTimeUnixNano'], '1704164645000000000');
      expect(record['timeUnixNano'], '1704164645000000000');
    });

    test('writes times past 2262 without overflowing', () {
      final String encoded = codec.encodeExportRequest(
        <AtTelemetryLogRecord>[
          AtTelemetryLogRecord(body: 'x', timestamp: DateTime.utc(2300)),
        ],
        observedAt: DateTime.utc(2024),
      );

      expect(_onlyRecord(encoded)['timeUnixNano'], '10413792000000000000');
    });

    test('writes the largest 64-bit integer as a string', () {
      final String encoded = codec.encodeExportRequest(
        <AtTelemetryLogRecord>[
          AtTelemetryLogRecord(
            attributes: const <String, Object?>{'max': 9223372036854775807},
          ),
        ],
      );

      expect(
        (_onlyRecord(encoded)['attributes']! as List<Object?>).single,
        <String, Object?>{
          'key': 'max',
          'value': <String, Object?>{'intValue': '9223372036854775807'},
        },
      );
    });

    test('throws ArgumentError when there are no records', () {
      expect(
        () => codec.encodeExportRequest(const <AtTelemetryLogRecord>[]),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for an observedAt OTLP cannot carry', () {
      final List<AtTelemetryLogRecord> records = <AtTelemetryLogRecord>[
        AtTelemetryLogRecord(eventName: 'a'),
      ];

      expect(
        () => codec.encodeExportRequest(
          records,
          observedAt: DateTime.utc(1969, 12, 31),
        ),
        throwsArgumentError,
      );
      expect(
        () => codec.encodeExportRequest(
          records,
          observedAt: DateTime.utc(2554, 7, 22),
        ),
        throwsArgumentError,
      );
    });

    test('defaults observedAt to now', () {
      final DateTime before = DateTime.now().toUtc();
      final Map<String, Object?> record = _onlyRecord(
        codec.encodeExportRequest(
          <AtTelemetryLogRecord>[AtTelemetryLogRecord(eventName: 'a')],
        ),
      );
      final DateTime after = DateTime.now().toUtc();

      final int observed =
          int.parse(record['observedTimeUnixNano']! as String) ~/ 1000;
      expect(observed, greaterThanOrEqualTo(before.microsecondsSinceEpoch));
      expect(observed, lessThanOrEqualTo(after.microsecondsSinceEpoch));
      expect(record['timeUnixNano'], record['observedTimeUnixNano']);
    });

    test('writes the epoch as 0', () {
      final Map<String, Object?> record = _onlyRecord(
        codec.encodeExportRequest(
          <AtTelemetryLogRecord>[
            AtTelemetryLogRecord(eventName: 'a', timestamp: DateTime.utc(1970)),
          ],
          observedAt: DateTime.utc(1970),
        ),
      );

      expect(record['timeUnixNano'], '0');
      expect(record['observedTimeUnixNano'], '0');
    });

    test('leaves out null attributes but keeps nulls inside a list', () {
      final Map<String, Object?> record = _onlyRecord(
        codec.encodeExportRequest(
          <AtTelemetryLogRecord>[
            AtTelemetryLogRecord(
              eventName: 'a',
              attributes: const <String, Object?>{
                'gone': null,
                'list': <Object?>[null],
              },
            ),
          ],
          observedAt: DateTime.utc(2024),
        ),
      );

      expect(record['attributes'], <Object?>[
        <String, Object?>{
          'key': 'list',
          'value': <String, Object?>{
            'arrayValue': <String, Object?>{
              'values': <Object?>[<String, Object?>{}],
            },
          },
        },
      ]);
    });

    test('writes an empty list and an empty map', () {
      final Map<String, Object?> record = _onlyRecord(
        codec.encodeExportRequest(
          <AtTelemetryLogRecord>[
            AtTelemetryLogRecord(
              eventName: 'a',
              attributes: const <String, Object?>{
                'list': <Object?>[],
                'map': <String, Object?>{},
              },
            ),
          ],
          observedAt: DateTime.utc(2024),
        ),
      );

      expect(record['attributes'], <Object?>[
        <String, Object?>{
          'key': 'list',
          'value': <String, Object?>{
            'arrayValue': <String, Object?>{'values': <Object?>[]},
          },
        },
        <String, Object?>{
          'key': 'map',
          'value': <String, Object?>{
            'kvlistValue': <String, Object?>{'values': <Object?>[]},
          },
        },
      ]);
    });
  });

  group('AtTelemetryLogsCodec.encode', () {
    test('writes one ResourceLogs per entry and skips empty ones', () {
      final String encoded = codec.encode(
        <AtTelemetryResourceLogs>[
          AtTelemetryResourceLogs(
            resourceAttributes: const <String, Object?>{'r': 'one'},
            scopeName: 'a',
            records: <AtTelemetryLogRecord>[
              AtTelemetryLogRecord(eventName: 'x'),
            ],
          ),
          AtTelemetryResourceLogs(
            scopeName: 'empty',
            records: const <AtTelemetryLogRecord>[],
          ),
          AtTelemetryResourceLogs(
            resourceAttributes: const <String, Object?>{'r': 'two'},
            scopeName: 'b',
            records: <AtTelemetryLogRecord>[
              AtTelemetryLogRecord(eventName: 'y'),
            ],
          ),
        ],
        observedAt: DateTime.utc(2024),
      );
      final List<AtTelemetryResourceLogs> decoded = codec.decode(encoded);

      expect(
        decoded.map((AtTelemetryResourceLogs logs) => logs.scopeName),
        <String>['a', 'b'],
      );
      expect(
        decoded.map(
          (AtTelemetryResourceLogs logs) => logs.resourceAttributes['r'],
        ),
        <String>['one', 'two'],
      );
    });

    test('throws ArgumentError when every entry is empty', () {
      expect(
        () => codec.encode(<AtTelemetryResourceLogs>[
          AtTelemetryResourceLogs(
            scopeName: 'empty',
            records: const <AtTelemetryLogRecord>[],
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('AtTelemetryLogsCodec.encodeExportResponse', () {
    test('is an empty ExportLogsServiceResponse', () {
      expect(codec.encodeExportResponse(), '{}');
      expect(jsonDecode(codec.encodeExportResponse()), isEmpty);
    });
  });

  group('AtTelemetryLogsCodec.decode', () {
    // The logs example from opentelemetry-proto's examples/logs.json, plus an
    // eventName as in examples/events.json
    const String specExample = '''
{
  "resourceLogs": [{
    "resource": {"attributes": [
      {"key": "service.name", "value": {"stringValue": "my.service"}}]},
    "scopeLogs": [{
      "scope": {"name": "my.library", "version": "1.0.0", "attributes": [
        {"key": "my.scope.attribute",
         "value": {"stringValue": "some scope attribute"}}]},
      "logRecords": [{
        "timeUnixNano": "1544712660300000000",
        "observedTimeUnixNano": "1544712660300000000",
        "severityNumber": 10,
        "severityText": "Information",
        "traceId": "5B8EFFF798038103D269B633813FC60C",
        "spanId": "EEE19B7EC3C1B174",
        "eventName": "browser.page_view",
        "body": {"stringValue": "Example log record"},
        "attributes": [
          {"key": "string.attribute", "value": {"stringValue": "some string"}},
          {"key": "boolean.attribute", "value": {"boolValue": true}},
          {"key": "int.attribute", "value": {"intValue": "10"}},
          {"key": "double.attribute", "value": {"doubleValue": 637.704}},
          {"key": "array.attribute", "value": {"arrayValue": {"values": [
            {"stringValue": "many"}, {"stringValue": "values"}]}}},
          {"key": "map.attribute", "value": {"kvlistValue": {"values": [
            {"key": "some.map.key",
             "value": {"stringValue": "some value"}}]}}}]
      }]
    }]
  }]
}
''';

    test('reads the specification\'s example', () {
      final List<AtTelemetryResourceLogs> decoded = codec.decode(specExample);

      expect(decoded, hasLength(1));
      final AtTelemetryResourceLogs logs = decoded.single;
      expect(logs.resourceAttributes, <String, Object?>{
        'service.name': 'my.service',
      });
      expect(logs.scopeName, 'my.library');
      final AtTelemetryLogRecord record = logs.records.single;
      expect(record.timestamp, DateTime.utc(2018, 12, 13, 14, 51, 0, 300));
      expect(record.observedTimestamp, record.timestamp);
      expect(record.severityNumber, AtTelemetrySeverity.info2);
      expect(record.severityText, 'Information');
      expect(record.eventName, 'browser.page_view');
      expect(record.body, 'Example log record');
      expect(record.attributes, <String, Object?>{
        'string.attribute': 'some string',
        'boolean.attribute': true,
        'int.attribute': 10,
        'double.attribute': 637.704,
        'array.attribute': <Object?>['many', 'values'],
        'map.attribute': <String, Object?>{'some.map.key': 'some value'},
      });
    });

    test('round trips what it encodes', () {
      final AtTelemetryLogRecord original = AtTelemetryLogRecord(
        eventName: 'login',
        body: <String, Object?>{
          'list': <Object?>[1, 'a', null, 2.5],
        },
        timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7),
        observedTimestamp: DateTime.utc(2024, 1, 2, 3, 4, 6),
        severityNumber: AtTelemetrySeverity.error,
        severityText: 'ERROR',
        attributes: <String, Object?>{
          'a': 1,
          'b': 2.5,
          'c': true,
          'bytes': Uint8List.fromList(<int>[0, 255]),
        },
      );
      final AtTelemetryLogRecord decoded = codec
          .decode(codec.encodeExportRequest(<AtTelemetryLogRecord>[original]))
          .single
          .records
          .single;

      expect(decoded.eventName, original.eventName);
      expect(decoded.body, original.body);
      expect(decoded.timestamp, original.timestamp);
      expect(decoded.observedTimestamp, original.observedTimestamp);
      expect(decoded.severityNumber, original.severityNumber);
      expect(decoded.severityText, original.severityText);
      expect(decoded.attributes, original.attributes);
      expect(decoded.attributes['bytes'], isA<Uint8List>());
    });

    test('accepts JSON numbers where strings are expected', () {
      final AtTelemetryLogRecord record = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"timeUnixNano":1544712660300000000,'
              '"attributes":[{"key":"i","value":{"intValue":10}}]}]}]}]}')
          .single
          .records
          .single;

      expect(record.timestamp, DateTime.utc(2018, 12, 13, 14, 51, 0, 300));
      expect(record.attributes, <String, Object?>{'i': 10});
    });

    test('treats a zero or missing time as unknown', () {
      final AtTelemetryLogRecord record = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"timeUnixNano":"0","body":{"stringValue":"x"}}]}]}]}')
          .single
          .records
          .single;

      expect(record.timestamp, isNull);
      expect(record.observedTimestamp, isNull);
    });

    test('reads times past 2262', () {
      final AtTelemetryLogRecord record = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"timeUnixNano":"10413792000000000000"}]}]}]}')
          .single
          .records
          .single;

      expect(record.timestamp, DateTime.utc(2300));
    });

    test('splits each ScopeLogs into its own entry', () {
      final List<AtTelemetryResourceLogs> decoded = codec.decode(
        '{"resourceLogs":[{"resource":{"attributes":[{"key":"r",'
        '"value":{"stringValue":"1"}}]},"scopeLogs":['
        '{"scope":{"name":"a"},"logRecords":[{"eventName":"x"}]},'
        '{"scope":{"name":"b"},"logRecords":[{"eventName":"y"}]},'
        '{"scope":{"name":"empty"},"logRecords":[]}]}]}',
      );

      expect(decoded.map((AtTelemetryResourceLogs logs) => logs.scopeName),
          <String>['a', 'b']);
      expect(decoded.first.resourceAttributes, <String, Object?>{'r': '1'});
      expect(decoded.last.resourceAttributes, <String, Object?>{'r': '1'});
    });

    test('calls a ScopeLogs without a scope the empty scope', () {
      final AtTelemetryResourceLogs logs = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{}]}]}]}')
          .single;

      expect(logs.scopeName, '');
      expect(logs.resourceAttributes, isEmpty);
    });

    test('reads severityNumber 0 and empty strings as unset', () {
      final AtTelemetryLogRecord record = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"severityNumber":0,"severityText":"","eventName":""}]}]}]}')
          .single
          .records
          .single;

      expect(record.severityNumber, isNull);
      expect(record.severityText, isNull);
      expect(record.eventName, isNull);
      expect(record.isEvent, isFalse);
    });

    test('reads an empty AnyValue, or one of an unknown kind, as null', () {
      final AtTelemetryLogRecord record = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"body":{},"attributes":['
              '{"key":"empty","value":{}},'
              '{"key":"unknown","value":{"futureValue":1}},'
              '{"key":"missing"}]}]}]}]}')
          .single
          .records
          .single;

      expect(record.body, isNull);
      expect(record.attributes, <String, Object?>{
        'empty': null,
        'unknown': null,
        'missing': null,
      });
    });

    test('reads an integer doubleValue as a double', () {
      final Object? value = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"attributes":[{"key":"d","value":{"doubleValue":5}}]}]}]}]}')
          .single
          .records
          .single
          .attributes['d'];

      expect(value, isA<double>());
      expect(value, 5.0);
    });

    test('reads the smallest and largest 64-bit integers', () {
      final Map<String, Object?> attributes = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"attributes":['
              '{"key":"min","value":{"intValue":"-9223372036854775808"}},'
              '{"key":"max","value":{"intValue":"9223372036854775807"}}'
              ']}]}]}]}')
          .single
          .records
          .single
          .attributes;

      expect(attributes['min'], -9223372036854775807 - 1);
      expect(attributes['max'], 9223372036854775807);
    });

    test('drops nanoseconds below a microsecond', () {
      final AtTelemetryLogRecord record = codec
          .decode('{"resourceLogs":[{"scopeLogs":[{"logRecords":[{'
              '"timeUnixNano":"1544712660300000999"}]}]}]}')
          .single
          .records
          .single;

      expect(record.timestamp, DateTime.utc(2018, 12, 13, 14, 51, 0, 300));
    });

    test('returns lists and maps that cannot be modified', () {
      final AtTelemetryResourceLogs logs = codec
          .decode(
            '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"attributes":['
            '{"key":"l","value":{"arrayValue":{"values":[]}}},'
            '{"key":"m","value":{"kvlistValue":{"values":[]}}}]}]}]}]}',
          )
          .single;
      final Map<String, Object?> attributes = logs.records.single.attributes;

      expect(
        () => (attributes['l']! as List<Object?>).add(1),
        throwsUnsupportedError,
      );
      expect(
        () => (attributes['m']! as Map<String, Object?>)['k'] = 1,
        throwsUnsupportedError,
      );
      expect(() => attributes['x'] = 1, throwsUnsupportedError);
      expect(
        () => logs.records.add(AtTelemetryLogRecord()),
        throwsUnsupportedError,
      );
    });

    final Map<String, String> invalid = <String, String>{
      'it is not JSON': 'not json',
      'it is not an object': '[]',
      'resourceLogs is not an array': '{"resourceLogs":{}}',
      'there are no records': '{"resourceLogs":[]}',
      'a record is not an object':
          '{"resourceLogs":[{"scopeLogs":[{"logRecords":[1]}]}]}',
      'timeUnixNano is negative': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"timeUnixNano":"-1"}]}]}]}',
      'timeUnixNano is past uint64': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"timeUnixNano":"99999999999999999999"}]}]}]}',
      'severityNumber is 25': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"severityNumber":25}]}]}]}',
      'severityNumber is a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"severityNumber":"9"}]}]}]}',
      'eventName is not a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"eventName":1}]}]}]}',
      'intValue is not an integer': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"attributes":[{"key":"i",'
          '"value":{"intValue":"1.5"}}]}]}]}]}',
      'intValue overflows 64 bits': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"attributes":[{"key":"i",'
          '"value":{"intValue":"9223372036854775808"}}]}]}]}]}',
      'doubleValue is NaN': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"attributes":[{"key":"d",'
          '"value":{"doubleValue":"NaN"}}]}]}]}]}',
      'bytesValue is not base64': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"attributes":[{"key":"b",'
          '"value":{"bytesValue":"!!"}}]}]}]}]}',
      'an attribute key is missing': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"attributes":[{"value":{"boolValue":true}}]}]}]}]}',
      'resource is not an object':
          '{"resourceLogs":[{"resource":1,"scopeLogs":[{"logRecords":[{}]}]}]}',
      'scopeLogs is not an array':
          '{"resourceLogs":[{"scopeLogs":{"logRecords":[{}]}}]}',
      'logRecords is not an array':
          '{"resourceLogs":[{"scopeLogs":[{"logRecords":{}}]}]}',
      'attributes is not an array': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"attributes":{}}]}]}]}',
      'scope.name is not a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"scope":{"name":1},"logRecords":[{}]}]}]}',
      'severityText is not a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"severityText":1}]}]}]}',
      'severityNumber is negative': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"severityNumber":-1}]}]}]}',
      'timeUnixNano is a boolean': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"timeUnixNano":true}]}]}]}',
      'timeUnixNano is past 2554': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"timeUnixNano":"18446744073709551615"}]}]}]}',
      'stringValue is not a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"stringValue":1}}]}]}]}',
      'boolValue is not a boolean': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"boolValue":"true"}}]}]}]}',
      'intValue is a boolean': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"intValue":true}}]}]}]}',
      'intValue underflows 64 bits': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"intValue":"-9223372036854775809"}}]}]}]}',
      'doubleValue is a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"doubleValue":"1.5"}}]}]}]}',
      'bytesValue is not a string': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"bytesValue":[1]}}]}]}]}',
      'arrayValue is not an object': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"arrayValue":[]}}]}]}]}',
      'an arrayValue item is not an object': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"arrayValue":{"values":[1]}}}]}]}]}',
      'kvlistValue is not an object': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"kvlistValue":[]}}]}]}]}',
      'a kvlistValue key is missing': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":{"kvlistValue":{"values":['
          '{"value":{}}]}}}]}]}]}',
      'a body is not an object': '{"resourceLogs":[{"scopeLogs":[{'
          '"logRecords":[{"body":"text"}]}]}]}',
    };
    for (final MapEntry<String, String> entry in invalid.entries) {
      test('throws FormatException when ${entry.key}', () {
        expect(() => codec.decode(entry.value), throwsFormatException);
      });
    }
  });
}

Map<String, Object?> _onlyRecord(String encoded) {
  final Map<String, Object?> request =
      jsonDecode(encoded) as Map<String, Object?>;
  final Map<String, Object?> resourceLogs =
      (request['resourceLogs']! as List<Object?>).single!
          as Map<String, Object?>;
  final Map<String, Object?> scopeLogs =
      (resourceLogs['scopeLogs']! as List<Object?>).single!
          as Map<String, Object?>;
  return (scopeLogs['logRecords']! as List<Object?>).single!
      as Map<String, Object?>;
}
