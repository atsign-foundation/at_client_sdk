import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryResource', () {
    test('stores serviceName as the service.name attribute', () {
      final AtTelemetryResource resource = AtTelemetryResource(
        serviceName: 'svc',
        attributes: const <String, Object?>{'atsign': '@alice'},
      );

      expect(resource.serviceName, 'svc');
      expect(resource.attributes, <String, Object?>{
        'atsign': '@alice',
        AtTelemetryResource.serviceNameAttribute: 'svc',
      });
    });

    test('serviceName wins over a service.name attribute', () {
      final AtTelemetryResource resource = AtTelemetryResource(
        serviceName: 'svc',
        attributes: const <String, Object?>{
          AtTelemetryResource.serviceNameAttribute: 'other',
        },
      );

      expect(resource.serviceName, 'svc');
    });

    test('rejects a blank serviceName', () {
      expect(() => AtTelemetryResource(serviceName: ''), throwsArgumentError);
      expect(() => AtTelemetryResource(serviceName: '  '), throwsArgumentError);
    });

    test('rejects an attribute that is not an AnyValue', () {
      expect(
        () => AtTelemetryResource(
          serviceName: 'svc',
          attributes: <String, Object?>{'when': DateTime.utc(2024)},
        ),
        throwsArgumentError,
      );
    });

    test('attributes cannot be modified', () {
      final AtTelemetryResource resource =
          AtTelemetryResource(serviceName: 'svc');

      expect(() => resource.attributes['x'] = 1, throwsUnsupportedError);
    });
  });
}
