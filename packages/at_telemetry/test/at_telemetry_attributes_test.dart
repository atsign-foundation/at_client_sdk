import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryAttributes', () {
    // These names are a wire contract with the collector, so a rename must
    // break a test
    test('uses the OpenTelemetry names for resource attributes', () {
      expect(AtTelemetryAttributes.serviceName, 'service.name');
      expect(AtTelemetryAttributes.serviceVersion, 'service.version');
      expect(AtTelemetryAttributes.serviceInstanceId, 'service.instance.id');
    });

    test('uses atsign.* names for the atSign specific attributes', () {
      expect(AtTelemetryAttributes.atServerId, 'atsign.atserver.id');
      expect(AtTelemetryAttributes.enrollmentId, 'atsign.enrollment.id');
      expect(AtTelemetryAttributes.clientId, 'atsign.client.id');
      expect(AtTelemetryAttributes.notificationIds, 'atsign.notification.ids');
      expect(AtTelemetryAttributes.keys, 'atsign.keys');
    });

    test('uses an atsign.* name for the heartbeat attribute', () {
      expect(
        AtTelemetryAttributes.atServerUptimeSeconds,
        'atsign.atserver.uptime_seconds',
      );
    });
  });
}
