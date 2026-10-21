import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryDroppedException', () {
    test('keeps the record that was dropped', () {
      final AtTelemetryLogRecord record = AtTelemetryLogRecord(eventName: 'a');

      expect(AtTelemetryDroppedException(record).logRecord, same(record));
    });

    test('names the event in its message', () {
      final AtTelemetryDroppedException exception =
          AtTelemetryDroppedException(AtTelemetryLogRecord(eventName: 'login'));

      expect(
        exception.toString(),
        'AtTelemetryDroppedException: login was not delivered',
      );
    });

    test('calls a plain log a log record in its message', () {
      final AtTelemetryDroppedException exception =
          AtTelemetryDroppedException(AtTelemetryLogRecord(body: 'hello'));

      expect(
        exception.toString(),
        'AtTelemetryDroppedException: log record was not delivered',
      );
    });
  });
}
