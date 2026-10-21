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

    group('app', () {
      test('uses the OTel attribute names', () {
        expect(
          AtTelemetryResource.app(
            serviceVersion: '1.2.3',
            serviceInstanceId: 'instance',
          ),
          <String, Object?>{
            AtTelemetryAttributes.serviceVersion: '1.2.3',
            AtTelemetryAttributes.serviceInstanceId: 'instance',
          },
        );
      });

      test('leaves out fields that are not given', () {
        expect(AtTelemetryResource.app(), isEmpty);
      });

      test('named fields win over attributes', () {
        expect(
          AtTelemetryResource.app(
            serviceVersion: '1.2.3',
            attributes: const <String, Object?>{
              AtTelemetryAttributes.serviceVersion: 'other',
              'deployment.environment.name': 'prod',
            },
          ),
          <String, Object?>{
            AtTelemetryAttributes.serviceVersion: '1.2.3',
            'deployment.environment.name': 'prod',
          },
        );
      });
    });

    group('atServer', () {
      test('sets the atServer id with the other fields', () {
        expect(
          AtTelemetryResource.atServer(
            atServerId: 'server',
            serviceVersion: '3.0.0',
            serviceInstanceId: 'boot',
          ),
          <String, Object?>{
            AtTelemetryAttributes.serviceVersion: '3.0.0',
            AtTelemetryAttributes.serviceInstanceId: 'boot',
            AtTelemetryAttributes.atServerId: 'server',
          },
        );
      });

      test('atServerId wins over attributes', () {
        expect(
          AtTelemetryResource.atServer(
            atServerId: 'server',
            attributes: const <String, Object?>{
              AtTelemetryAttributes.atServerId: 'other',
            },
          ),
          <String, Object?>{AtTelemetryAttributes.atServerId: 'server'},
        );
      });

      test('rejects a blank atServerId', () {
        expect(
          () => AtTelemetryResource.atServer(atServerId: ' '),
          throwsArgumentError,
        );
      });
    });
  });
}
