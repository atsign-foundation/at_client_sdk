import 'dart:typed_data';

// OpenTelemetry AnyValues are null, String, bool, int, finite double,
// Uint8List, List of AnyValues, or Map<String, AnyValue>
final class AtTelemetryAnyValue {
  const AtTelemetryAnyValue._();

  static void check(Object? value, String path) {
    switch (value) {
      case null || String() || bool() || int() || Uint8List():
        return;
      case final double value:
        if (!value.isFinite) {
          throw ArgumentError.value(value, path, 'must be a finite double');
        }
      case final List<Object?> values:
        for (int index = 0; index < values.length; index++) {
          check(values[index], '$path[$index]');
        }
      case final Map<String, Object?> values:
        for (final MapEntry<String, Object?> entry in values.entries) {
          check(entry.value, '$path.${entry.key}');
        }
      default:
        throw ArgumentError.value(
          value,
          path,
          'must be null, String, bool, int, double, Uint8List, '
          'List, or Map<String, Object?>',
        );
    }
  }
}
