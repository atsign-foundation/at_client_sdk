import 'package:at_telemetry/at_telemetry.dart';
import 'package:crypton/crypton.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('sends exact OTLP bytes with a verifiable signature', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    int requests = 0;
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      client: MockClient((http.Request request) async {
        requests++;
        expect(request.url.path, '/v1/logs');
        final AtTelemetryHttpSignature signed = AtTelemetryHttpSignature.parse(
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
            const AtTelemetryLogsCodec()
                .decodeExportRequest(request.bodyBytes)
                .single
                .name,
            'atsign.server.heartbeat');
        return http.Response('', requests == 1 ? 503 : 200);
      }),
    );
    await exporter.export(AtTelemetryLogRecord(
      name: 'atsign.server.heartbeat',
      timestamp: DateTime.now().toUtc(),
      attributes: <String, Object?>{'atsign.atserver.id': '@producer1'},
    ));
    await exporter.shutdown();
    expect(requests, 2);
  });

  test('sends a signed OTLP gauge to /v1/metrics', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      client: MockClient((http.Request request) async {
        expect(request.url.path, '/v1/metrics');
        final AtTelemetryHttpSignature signed = AtTelemetryHttpSignature.parse(
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
        final AtTelemetryGauge gauge = const AtTelemetryMetricsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single as AtTelemetryGauge;
        expect(gauge.name, 'atsign.atserver.uptime');
        expect(gauge.unit, 's');
        expect(gauge.value, 42);
        return http.Response('', 200);
      }),
    );

    await exporter.exportMetrics(<AtTelemetryGauge>[
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

  test('exports logs, sums, histograms and spans in order with signed requests',
      () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<String> paths = <String>[];
    final DateTime start = DateTime.utc(2026, 9, 29);
    final DateTime end = start.add(const Duration(seconds: 1));
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'application',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      client: MockClient((http.Request request) async {
        paths.add(request.url.path);
        expect(request.followRedirects, isFalse);
        expect(request.headers, isNot(contains('authorization')));
        final AtTelemetryHttpSignature signature =
            AtTelemetryHttpSignature.parse(
          input: request.headers[AtTelemetryHttpSignature.inputHeader]!,
          signature: request.headers[AtTelemetryHttpSignature.signatureHeader]!,
          digest: request.headers[AtTelemetryHttpSignature.digestHeader]!,
          audience: request.headers[AtTelemetryHttpSignature.audienceHeader]!,
        );
        expect(signature.matchesBody(request.bodyBytes), isTrue);
        expect(
            await signature.verify(
                path: request.url.path, publicKey: keys.publicKey.toString()),
            isTrue);
        if (request.url.path == '/v1/metrics') {
          final List<AtTelemetryMetric> decoded =
              const AtTelemetryMetricsCodec()
                  .decodeExportRequest(request.bodyBytes);
          expect(decoded[0], isA<AtTelemetrySum>());
          expect(decoded[1], isA<AtTelemetryHistogram>());
          expect(decoded.first.attributes['service.name'], 'application');
        }
        if (request.url.path == '/v1/traces') {
          final AtTelemetrySpan span = const AtTelemetryTracesCodec()
              .decodeExportRequest(request.bodyBytes)
              .single;
          expect(span.name, 'lookup');
          expect(span.startTimestamp, start);
          expect(span.endTimestamp, end);
          expect(span.attributes['atsign.atserver.id'], '@producer1');
          expect(span.attributes['service.name'], 'application');
          expect(
              await signature.verify(
                  path: '/v1/metrics', publicKey: keys.publicKey.toString()),
              isFalse);
        }
        return http.Response('', 200);
      }),
    );

    final Future<void> logs = exporter
        .export(AtTelemetryLogRecord(name: 'started', timestamp: start));
    final Future<void> metrics = exporter.exportMetrics(<AtTelemetryMetric>[
      AtTelemetrySum(
          name: 'requests', value: 1, timestamp: end, startTimestamp: start),
      AtTelemetryHistogram(
          name: 'duration',
          count: 1,
          sum: 1,
          bucketCounts: const <int>[1],
          timestamp: end),
    ]);
    final Future<void> traces = exporter.exportSpans(<AtTelemetrySpan>[
      AtTelemetrySpan(
          name: 'lookup',
          traceId: '0123456789abcdef0123456789abcdef',
          spanId: '0123456789abcdef',
          startTimestamp: start,
          endTimestamp: end,
          attributes: const <String, Object?>{
            'atsign.atserver.id': '@producer1'
          }),
    ]);
    await exporter.flush();
    await Future.wait<void>(<Future<void>>[logs, metrics, traces]);
    await exporter.shutdown();

    expect(paths, <String>['/v1/logs', '/v1/metrics', '/v1/traces']);
    expect(
        () => exporter.exportMetrics(<AtTelemetryMetric>[]), throwsStateError);
    expect(() => exporter.exportSpans(<AtTelemetrySpan>[]), throwsStateError);
  });

  test('accepts any OTLP signal endpoint and routes spans to traces', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final DateTime timestamp = DateTime.utc(2026, 9, 29);
    for (final String path in <String>[
      '/v1/logs',
      '/v1/metrics',
      '/v1/traces'
    ]) {
      final List<String> delivered = <String>[];
      final AtTelemetrySignedHttpExporter exporter =
          AtTelemetrySignedHttpExporter(
        endpoint: Uri.parse('http://localhost:4318$path'),
        serviceName: 'application',
        keyId: '@producer1',
        audience: 'localhost',
        signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
        client: MockClient((http.Request request) async {
          delivered.add(request.url.path);
          return http.Response('', 200);
        }),
      );
      await exporter.exportSpans(<AtTelemetrySpan>[
        AtTelemetrySpan(
            name: 'lookup',
            traceId: '0123456789abcdef0123456789abcdef',
            spanId: '0123456789abcdef',
            startTimestamp: timestamp,
            endTimestamp: timestamp),
      ]);
      await exporter.shutdown();
      expect(delivered, <String>['/v1/traces']);
    }
  });

  test('invalid metric and span payloads are reported without sending HTTP',
      () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<Object> errors = <Object>[];
    int requests = 0;
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'application',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client: MockClient((http.Request request) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    await exporter.exportMetrics(<AtTelemetryMetric>[]);
    await exporter.exportSpans(<AtTelemetrySpan>[]);
    await exporter.shutdown();
    expect(errors, hasLength(2));
    expect(errors, everyElement(isA<ArgumentError>()));
    expect(requests, 0);
  });

  test('span rejection is best effort and does not block subsequent metrics',
      () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<Object> errors = <Object>[];
    final List<String> paths = <String>[];
    final DateTime timestamp = DateTime.utc(2026, 9, 29);
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'application',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client: MockClient((http.Request request) async {
        paths.add(request.url.path);
        return http.Response('', request.url.path == '/v1/traces' ? 401 : 200);
      }),
    );
    await exporter.exportSpans(<AtTelemetrySpan>[
      AtTelemetrySpan(
          name: 'lookup',
          traceId: '0123456789abcdef0123456789abcdef',
          spanId: '0123456789abcdef',
          startTimestamp: timestamp,
          endTimestamp: timestamp),
    ]);
    await exporter.exportMetrics(<AtTelemetryMetric>[
      AtTelemetrySum(name: 'requests', value: 1, timestamp: timestamp)
    ]);
    await exporter.shutdown();
    expect(errors, hasLength(1));
    expect(paths, <String>['/v1/traces', '/v1/metrics']);
  });

  test('best-effort export reports rejection through onError', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<Object> errors = <Object>[];
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client:
          MockClient((http.Request request) async => http.Response('', 401)),
    );

    await exporter.export(AtTelemetryLogRecord(
      name: 'atsign.atserver.heartbeat',
      timestamp: DateTime.now().toUtc(),
    ));
    await exporter.shutdown();

    expect(errors, hasLength(1));
  });

  test('confirms event delivery only after HTTP 200', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final AtTelemetryLogRecord event = AtTelemetryLogRecord(
      name: 'atsign.atserver.heartbeat',
      timestamp: DateTime.now().toUtc(),
      attributes: <String, Object?>{'atsign.atserver.id': '@producer1'},
    );
    final List<Object> errors = <Object>[];
    int requests = 0;
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'at_secondary_server',
      keyId: '@producer1',
      audience: '@telemetry1',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client: MockClient((http.Request request) async {
        requests++;
        final AtTelemetryHttpSignature signed = AtTelemetryHttpSignature.parse(
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
        final AtTelemetryLogRecord received = const AtTelemetryLogsCodec()
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
        const AtTelemetryLogsCodec().encodeExportRequest(<AtTelemetryLogRecord>[
      AtTelemetryLogRecord(
        name: 'atsign.atserver.heartbeat',
        timestamp: DateTime.now().toUtc(),
        attributes: <String, Object?>{'atsign.atserver.id': '@producer1'},
      ),
    ], serviceName: 'at_secondary_server');
    final List<String> signatureInputs = <String>[];
    final List<Object> errors = <Object>[];
    int requests = 0;
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
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
        final AtTelemetryHttpSignature signed = AtTelemetryHttpSignature.parse(
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
