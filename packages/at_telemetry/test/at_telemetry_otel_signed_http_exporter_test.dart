import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:crypton/crypton.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('sends exact OTLP bytes with a verifiable signature', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    int requests = 0;
    final AtTelemetryOtelSignedHttpExporter exporter =
        AtTelemetryOtelSignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      client: MockClient((http.Request request) async {
        requests++;
        expect(request.url.path, '/v1/logs');
        final AtTelemetryOtelHttpSignature signed =
            AtTelemetryOtelHttpSignature.parse(
          input: request.headers['signature-input']!,
          signature: request.headers['signature']!,
          digest: request.headers['content-digest']!,
          audience: request.headers['at-telemetry-audience']!,
        );
        expect(signed.matchesBody(request.bodyBytes), isTrue);
        expect(
            await signed.verify(
              path: request.url.path,
              publicKey: keys.publicKey.toString(),
            ),
            isTrue);
        expect(
            const AtTelemetryOtelLogsCodec()
                .decodeExportRequest(request.bodyBytes)
                .single
                .name,
            'atsign.server.heartbeat');
        return http.Response('', requests == 1 ? 503 : 200);
      }),
    );
    await exporter.export(AtTelemetryEvent(
      name: 'atsign.server.heartbeat',
      timestamp: DateTime.now().toUtc(),
      attributes: <String, Object?>{'atsign.atserver.id': '@producer1'},
    ));
    await exporter.shutdown();
    expect(requests, 2);
  });

  test('sends a signed OTLP gauge to /v1/metrics', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final AtTelemetryOtelSignedHttpExporter exporter =
        AtTelemetryOtelSignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      client: MockClient((http.Request request) async {
        expect(request.url.path, '/v1/metrics');
        final AtTelemetryOtelHttpSignature signed =
            AtTelemetryOtelHttpSignature.parse(
          input: request.headers['signature-input']!,
          signature: request.headers['signature']!,
          digest: request.headers['content-digest']!,
          audience: request.headers['at-telemetry-audience']!,
        );
        expect(signed.matchesBody(request.bodyBytes), isTrue);
        expect(
          await signed.verify(
            path: request.url.path,
            publicKey: keys.publicKey.toString(),
          ),
          isTrue,
        );
        final AtTelemetryGauge gauge = const AtTelemetryOtelMetricsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single;
        expect(gauge.name, 'atsign.atserver.uptime');
        expect(gauge.unit, 's');
        expect(gauge.value, 42);
        return http.Response('', 200);
      }),
    );

    await exporter.exportGauges(<AtTelemetryGauge>[
      AtTelemetryGauge(
        name: 'atsign.atserver.uptime',
        value: 42,
        unit: 's',
        timestamp: DateTime.now().toUtc(),
        attributes: const <String, Object?>{
          'atsign.atserver.id': '@producer1',
        },
      ),
    ]);
    await exporter.shutdown();
  });

  test('best-effort export reports rejection through onError', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<Object> errors = <Object>[];
    final AtTelemetryOtelSignedHttpExporter exporter =
        AtTelemetryOtelSignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client:
          MockClient((http.Request request) async => http.Response('', 401)),
    );

    await exporter.export(AtTelemetryEvent(
      name: 'atsign.atserver.heartbeat',
      timestamp: DateTime.now().toUtc(),
    ));
    await exporter.shutdown();

    expect(errors, hasLength(1));
  });

  test('confirms event delivery only after HTTP 200', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final AtTelemetryEvent event = AtTelemetryEvent(
      name: 'atsign.atserver.heartbeat',
      timestamp: DateTime.now().toUtc(),
      attributes: <String, Object?>{'atsign.atserver.id': '@producer1'},
    );
    final List<Object> errors = <Object>[];
    int requests = 0;
    final AtTelemetryOtelSignedHttpExporter exporter =
        AtTelemetryOtelSignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client: MockClient((http.Request request) async {
        requests++;
        final AtTelemetryOtelHttpSignature signed =
            AtTelemetryOtelHttpSignature.parse(
          input: request.headers['signature-input']!,
          signature: request.headers['signature']!,
          digest: request.headers['content-digest']!,
          audience: request.headers['at-telemetry-audience']!,
        );
        expect(signed.matchesBody(request.bodyBytes), isTrue);
        expect(
            await signed.verify(
              path: request.url.path,
              publicKey: keys.publicKey.toString(),
            ),
            isTrue);
        final AtTelemetryEvent received = const AtTelemetryOtelLogsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single;
        expect(received.name, event.name);
        expect(received.timestamp, event.timestamp);
        expect(received.attributes['atsign.atserver.id'], '@producer1');
        expect(received.attributes['service.name'], 'at_secondary_server');
        return http.Response('', requests == 1 ? 401 : 200);
      }),
    );

    await expectLater(
        exporter.sendConfirmed(event), throwsA(isA<StateError>()));
    await exporter.sendConfirmed(event);
    await exporter.shutdown();

    expect(requests, 2);
    expect(errors, hasLength(1));
  });

  test('sends stored bytes and reports failure before a later retry', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<int> payload =
        const AtTelemetryOtelLogsCodec().encodeExportRequest(<AtTelemetryEvent>[
      AtTelemetryEvent(
        name: 'atsign.atserver.heartbeat',
        timestamp: DateTime.now().toUtc(),
        attributes: <String, Object?>{'atsign.atserver.id': '@producer1'},
      ),
    ], serviceName: 'at_secondary_server');
    final List<String> signatureInputs = <String>[];
    final List<Object> errors = <Object>[];
    int requests = 0;
    final AtTelemetryOtelSignedHttpExporter exporter =
        AtTelemetryOtelSignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client: MockClient((http.Request request) async {
        requests++;
        expect(request.followRedirects, isFalse);
        expect(request.url.path, '/v1/logs');
        expect(request.bodyBytes, payload);
        final AtTelemetryOtelHttpSignature signed =
            AtTelemetryOtelHttpSignature.parse(
          input: request.headers['signature-input']!,
          signature: request.headers['signature']!,
          digest: request.headers['content-digest']!,
          audience: request.headers['at-telemetry-audience']!,
        );
        signatureInputs.add(request.headers['signature-input']!);
        expect(signed.matchesBody(payload), isTrue);
        expect(
            await signed.verify(
              path: request.url.path,
              publicKey: keys.publicKey.toString(),
            ),
            isTrue);
        return http.Response('', requests == 1 ? 302 : 200);
      }),
    );

    await expectLater(
        exporter.sendEncodedLogs(payload), throwsA(isA<StateError>()));
    await exporter.sendEncodedLogs(payload);
    await exporter.flush();
    await exporter.shutdown();

    expect(requests, 2);
    expect(errors, hasLength(1));
    expect(signatureInputs[0], isNot(signatureInputs[1]));
  });
}
