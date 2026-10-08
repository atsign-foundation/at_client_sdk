import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryLogRecord', () {
    test('converts the timestamps to UTC', () {
      final DateTime local = DateTime(2024, 1, 2, 3, 4, 5);
      final AtTelemetryLogRecord record = AtTelemetryLogRecord(
        timestamp: local,
        observedTimestamp: local,
      );

      expect(record.timestamp!.isUtc, isTrue);
      expect(record.timestamp, local.toUtc());
      expect(record.observedTimestamp!.isUtc, isTrue);
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

    group('timestamp range', () {
      test('rejects a time before 1970', () {
        expect(
          () => AtTelemetryLogRecord(timestamp: DateTime.utc(1969, 12, 31)),
          throwsArgumentError,
        );
        expect(
          () => AtTelemetryLogRecord(
            observedTimestamp: DateTime.utc(1969, 12, 31),
          ),
          throwsArgumentError,
        );
      });

      test('rejects a time OTLP nanoseconds cannot hold', () {
        expect(
          () => AtTelemetryLogRecord(timestamp: DateTime.utc(2554, 7, 22)),
          throwsArgumentError,
        );
      });

      test('accepts the limits themselves, and times past 2262', () {
        expect(
          () => AtTelemetryLogRecord(timestamp: DateTime.utc(1970)),
          returnsNormally,
        );
        expect(
          () => AtTelemetryLogRecord(timestamp: DateTime.utc(2300)),
          returnsNormally,
        );
        expect(
          () => AtTelemetryLogRecord(timestamp: DateTime.utc(2554, 7, 21)),
          returnsNormally,
        );
      });
    });

    test('isEvent is true only for a non-empty eventName', () {
      expect(AtTelemetryLogRecord().isEvent, isFalse);
      expect(AtTelemetryLogRecord(eventName: '').isEvent, isFalse);
      expect(AtTelemetryLogRecord(eventName: 'login').isEvent, isTrue);
    });

    group('withDefaultAttributes', () {
      test('adds attributes the record does not already have', () {
        final AtTelemetryLogRecord record = AtTelemetryLogRecord(
          eventName: 'login',
          body: 'b',
          timestamp: DateTime.utc(2024),
          severityNumber: AtTelemetrySeverity.info,
          attributes: const <String, Object?>{'a': 1},
        ).withDefaultAttributes(const <String, Object?>{'b': 2});

        expect(record.attributes, <String, Object?>{'a': 1, 'b': 2});
        expect(record.eventName, 'login');
        expect(record.body, 'b');
        expect(record.timestamp, DateTime.utc(2024));
        expect(record.severityNumber, AtTelemetrySeverity.info);
      });

      test('keeps the record\'s own value on a clash', () {
        final AtTelemetryLogRecord record = AtTelemetryLogRecord(
          attributes: const <String, Object?>{'a': 'mine'},
        ).withDefaultAttributes(const <String, Object?>{'a': 'default'});

        expect(record.attributes['a'], 'mine');
      });
    });
  });
}
