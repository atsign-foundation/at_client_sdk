import 'dart:typed_data';

import 'package:at_telemetry/src/at_telemetry_any_value.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryAnyValue.check', () {
    test('accepts every AnyValue type', () {
      final List<Object?> values = <Object?>[
        null,
        'text',
        true,
        42,
        1.5,
        Uint8List.fromList(<int>[1, 2]),
        <Object?>[],
        <Object?>[1, 'a', null],
        <String, Object?>{},
        <String, Object?>{
          'nested': <String, Object?>{
            'list': <Object?>[1, 2.5, false],
          },
        },
      ];
      for (final Object? value in values) {
        expect(
            () => AtTelemetryAnyValue.check(value, 'value'), returnsNormally);
      }
    });

    test('rejects non-finite doubles', () {
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => AtTelemetryAnyValue.check(value, 'value'),
          throwsArgumentError,
        );
      }
    });

    test('rejects values that are not AnyValues', () {
      final List<Object?> values = <Object?>[
        DateTime.utc(2024),
        <int>{1},
        <int, Object?>{1: 'a'},
        Object(),
      ];
      for (final Object? value in values) {
        expect(
          () => AtTelemetryAnyValue.check(value, 'value'),
          throwsArgumentError,
        );
      }
    });

    test('names the path of a nested invalid value', () {
      expect(
        () => AtTelemetryAnyValue.check(
          <String, Object?>{
            'a': <Object?>[
              1,
              <String, Object?>{'b': DateTime.utc(2024)},
            ],
          },
          'attributes',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'attributes.a[1].b',
          ),
        ),
      );
    });
  });
}
