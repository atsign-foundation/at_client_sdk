import 'dart:convert';
import 'dart:typed_data';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryLogRecord', () {
    test('converts the timestamp to UTC', () {
      final DateTime local = DateTime(2024, 1, 2, 3, 4, 5);
      final AtTelemetryLogRecord record =
          AtTelemetryLogRecord(timestamp: local);

      expect(record.timestamp!.isUtc, isTrue);
      expect(record.timestamp, local.toUtc());
    });

    test('copies attributes and makes them unmodifiable', () {
      final Map<String, Object?> source = <String, Object?>{'a': 1};
      final AtTelemetryLogRecord record =
          AtTelemetryLogRecord(attributes: source);
      source['a'] = 2;

      expect(record.attributes, <String, Object?>{'a': 1});
      expect(() => record.attributes['b'] = 1, throwsUnsupportedError);
    });

    test('rejects a body that is not an AnyValue', () {
      expect(
        () => AtTelemetryLogRecord(body: DateTime.utc(2024)),
        throwsArgumentError,
      );
    });

    test('rejects an attribute that is not an AnyValue', () {
      expect(
        () => AtTelemetryLogRecord(
          attributes: <String, Object?>{'when': DateTime.utc(2024)},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'attributes.when',
          ),
        ),
      );
    });

    test('isEvent is true only for a non-empty eventName', () {
      expect(AtTelemetryLogRecord().isEvent, isFalse);
      expect(AtTelemetryLogRecord(eventName: '').isEvent, isFalse);
      expect(AtTelemetryLogRecord(eventName: 'login').isEvent, isTrue);
    });

    group('toJson', () {
      test('omits null fields but always includes attributes', () {
        expect(
          AtTelemetryLogRecord().toJson(),
          <String, Object?>{'attributes': <String, Object?>{}},
        );
      });

      test('writes every field', () {
        final AtTelemetryLogRecord record = AtTelemetryLogRecord(
          eventName: 'login',
          body: 'hello',
          timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5, 6),
          severityNumber: AtTelemetrySeverity.warn,
          severityText: 'WARN',
          attributes: const <String, Object?>{'a': 1},
        );

        expect(record.toJson(), <String, Object?>{
          'eventName': 'login',
          'body': 'hello',
          'timestamp': '2024-01-02T03:04:05.006Z',
          'severityNumber': 13,
          'severityText': 'WARN',
          'attributes': <String, Object?>{'a': 1},
        });
      });
    });

    group('fromJson', () {
      test('round trips through JSON', () {
        final AtTelemetryLogRecord record = AtTelemetryLogRecord(
          eventName: 'login',
          body: <String, Object?>{
            'list': <Object?>[1, 'a', null],
          },
          timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7),
          severityNumber: AtTelemetrySeverity.error,
          severityText: 'ERROR',
          attributes: const <String, Object?>{'a': 1, 'b': 2.5, 'c': true},
        );

        final AtTelemetryLogRecord decoded = AtTelemetryLogRecord.fromJson(
          jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
        );

        expect(decoded.toJson(), record.toJson());
      });

      test('reads a Uint8List body back as a List of ints', () {
        final AtTelemetryLogRecord record = AtTelemetryLogRecord(
          body: Uint8List.fromList(<int>[1, 2, 3]),
        );

        final AtTelemetryLogRecord decoded = AtTelemetryLogRecord.fromJson(
          jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
        );

        expect(decoded.body, isNot(isA<Uint8List>()));
        expect(decoded.body, <int>[1, 2, 3]);
      });

      test('defaults missing fields', () {
        final AtTelemetryLogRecord record =
            AtTelemetryLogRecord.fromJson(const <String, Object?>{});

        expect(record.eventName, isNull);
        expect(record.body, isNull);
        expect(record.timestamp, isNull);
        expect(record.severityNumber, isNull);
        expect(record.severityText, isNull);
        expect(record.attributes, isEmpty);
      });

      final Map<String, Map<String, Object?>> invalid =
          <String, Map<String, Object?>>{
        'eventName is not a string': <String, Object?>{'eventName': 1},
        'timestamp is not a string': <String, Object?>{'timestamp': 1},
        'timestamp is not ISO-8601': <String, Object?>{'timestamp': 'later'},
        'severityNumber is not an int': <String, Object?>{
          'severityNumber': '9',
        },
        'severityNumber is 0': <String, Object?>{'severityNumber': 0},
        'severityNumber is 25': <String, Object?>{'severityNumber': 25},
        'severityText is not a string': <String, Object?>{'severityText': 9},
        'attributes is not an object': <String, Object?>{
          'attributes': <Object?>[],
        },
        'body is not an AnyValue': <String, Object?>{
          'body': DateTime.utc(2024),
        },
      };
      for (final MapEntry<String, Map<String, Object?>> entry
          in invalid.entries) {
        test('throws FormatException when ${entry.key}', () {
          expect(
            () => AtTelemetryLogRecord.fromJson(entry.value),
            throwsFormatException,
          );
        });
      }
    });
  });
}
