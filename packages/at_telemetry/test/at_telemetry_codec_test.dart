import 'dart:convert';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:test/test.dart';

void main() {
  final AtTelemetryEvent event = AtTelemetryEvent(
    name: 'atsign.app.started',
    timestamp: DateTime.utc(2026, 2, 25, 9, 30, 0, 0, 123),
    attributes: const <String, Object?>{
      'app.version': '1.2.3',
      'app.retries': 2,
      'app.ratio': 0.5,
      'app.debug': false,
      'app.tags': <Object?>['a', 'b'],
      'app.device': <String, Object?>{'os': 'linux'},
      'app.optional': null,
    },
  );

  test('round-trips an event through JSON', () {
    final AtTelemetryEvent decoded = AtTelemetryEvent.fromJson(
      jsonDecode(jsonEncode(event.toJson())) as Map<String, Object?>,
    );

    expect(decoded.name, event.name);
    expect(decoded.timestamp, event.timestamp);
    expect(decoded.attributes, event.attributes);
  });

  test('rejects JSON without an event name', () {
    expect(
      () => AtTelemetryEvent.fromJson(<String, Object?>{
        'timestamp': '2026-02-25T09:30:00.000Z',
      }),
      throwsFormatException,
    );
  });

  test('round-trips events through OTLP encoding', () {
    const AtTelemetryOtelLogsCodec codec = AtTelemetryOtelLogsCodec();
    final List<AtTelemetryEvent> decoded = codec.decodeExportRequest(
      codec.encodeExportRequest(<AtTelemetryEvent>[event], serviceName: 'app'),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.name, event.name);
    expect(decoded.single.timestamp, event.timestamp);
    expect(decoded.single.attributes['service.name'], 'app');
    expect(decoded.single.attributes['app.retries'], 2);
    expect(decoded.single.attributes['app.tags'], <Object?>['a', 'b']);
    expect(
      decoded.single.attributes['app.device'],
      <String, Object?>{'os': 'linux'},
    );
    expect(decoded.single.attributes, isNot(contains('app.optional')));
  });

  test('refuses to encode unsupported attribute values', () {
    expect(
      () => const AtTelemetryOtelLogsCodec().encodeExportRequest(
        <AtTelemetryEvent>[
          AtTelemetryEvent(
            name: 'atsign.app.started',
            timestamp: DateTime.utc(2026),
            attributes: <String, Object?>{'when': DateTime.utc(2026)},
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('round-trips events through the notification codec', () {
    const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
    final List<AtTelemetryEvent> decoded = codec.decode(
      codec.encode(<AtTelemetryEvent>[event]),
    );

    expect(decoded.single.name, event.name);
    expect(decoded.single.timestamp, event.timestamp);
  });

  test('rejects a notification payload that is not base64', () {
    expect(
      () => const AtTelemetryNotificationCodec().decode('not base64!'),
      throwsFormatException,
    );
  });
}
