import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetrySeverity', () {
    test('has 24 levels numbered 1 to 24 in order', () {
      expect(AtTelemetrySeverity.values, hasLength(24));
      for (int index = 0; index < AtTelemetrySeverity.values.length; index++) {
        expect(AtTelemetrySeverity.values[index].number, index + 1);
      }
    });

    test('fromNumber returns the matching level', () {
      expect(AtTelemetrySeverity.fromNumber(1), AtTelemetrySeverity.trace);
      expect(AtTelemetrySeverity.fromNumber(9), AtTelemetrySeverity.info);
      expect(AtTelemetrySeverity.fromNumber(17), AtTelemetrySeverity.error);
      expect(AtTelemetrySeverity.fromNumber(24), AtTelemetrySeverity.fatal4);
    });

    test('fromNumber returns null outside 1 to 24', () {
      expect(AtTelemetrySeverity.fromNumber(0), isNull);
      expect(AtTelemetrySeverity.fromNumber(-1), isNull);
      expect(AtTelemetrySeverity.fromNumber(25), isNull);
    });

    test('shortName is the upper case OTel name', () {
      expect(AtTelemetrySeverity.info.shortName, 'INFO');
      expect(AtTelemetrySeverity.error2.shortName, 'ERROR2');
    });
  });
}
