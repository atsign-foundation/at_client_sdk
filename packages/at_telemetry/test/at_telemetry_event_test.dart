import 'package:test/test.dart';
import 'package:at_telemetry/at_telemetry.dart';

void main() {
  test('create an event with producer-suppleid data', () {
    final DateTime timestamp = DateTime.utc(2026, 2, 23, 12);
    final Map<String, Object?> attributes = <String, Object?>{
      'verb': 'lookup',
      'success': true,
    };

    final AtTelemetryEvent event = AtTelemetryEvent(
      name: 'at_server.request',
      timestamp: timestamp,
      attributes: attributes,
    );

    expect(event.name, 'at_server.request');
    expect(event.timestamp, timestamp);
    expect(event.attributes, attributes);
  });
}
