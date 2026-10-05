import 'dart:async';

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

  test('exports logs in order with signed requests', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<String> names = <String>[];
    final DateTime start = DateTime.utc(2026, 9, 29);
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'application',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      client: MockClient((http.Request request) async {
        expect(request.url.path, '/v1/logs');
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
        final AtTelemetryLogRecord log = const AtTelemetryLogsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single;
        expect(log.attributes['service.name'], 'application');
        names.add(log.name);
        return http.Response('', 200);
      }),
    );

    final List<Future<void>> exports = <Future<void>>[
      for (final String name in <String>['started', 'connected', 'stopped'])
        exporter.export(AtTelemetryLogRecord(name: name, timestamp: start)),
    ];
    await exporter.flush();
    await Future.wait<void>(exports);
    await exporter.shutdown();

    expect(names, <String>['started', 'connected', 'stopped']);
    expect(
      () =>
          exporter.export(AtTelemetryLogRecord(name: 'late', timestamp: start)),
      throwsStateError,
    );
  });

  test('encodes telemetry at export time so later changes are not sent',
      () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final DateTime timestamp = DateTime.utc(2026, 9, 29);
    final List<http.Request> requests = <http.Request>[];
    final List<Object> errors = <Object>[];
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'application',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      client: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response('', 200);
      }),
    );

    final Map<String, Object?> logAttributes = <String, Object?>{};
    for (int index = 0; index < 3; index++) {
      logAttributes['index'] = index;
      exporter.export(AtTelemetryLogRecord(
          name: 'loop', timestamp: timestamp, attributes: logAttributes));
    }
    logAttributes
      ..clear()
      ..['when'] = DateTime.utc(2026);

    await exporter.shutdown();

    expect(errors, isEmpty);
    expect(requests.map((http.Request request) => request.url.path), <String>[
      '/v1/logs',
      '/v1/logs',
      '/v1/logs',
    ]);
    expect(<Object?>[
      for (final http.Request request in requests.take(3))
        const AtTelemetryLogsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single
            .attributes['index'],
    ], <Object?>[
      0,
      1,
      2
    ]);
  });

  test('discards the oldest queued exports when the backlog is full', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final DateTime timestamp = DateTime.utc(2026, 9, 29);
    final Completer<void> release = Completer<void>();
    final List<String> delivered = <String>[];
    final List<Object> errors = <Object>[];
    final AtTelemetrySignedHttpExporter exporter =
        AtTelemetrySignedHttpExporter(
      endpoint: Uri.parse('http://localhost:4318'),
      serviceName: 'application',
      keyId: '@producer1',
      audience: 'localhost',
      signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
      onError: errors.add,
      maxQueuedExports: 2,
      client: MockClient((http.Request request) async {
        await release.future;
        delivered.add(const AtTelemetryLogsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single
            .name);
        return http.Response('', 200);
      }),
    );
    AtTelemetryLogRecord log(String name) =>
        AtTelemetryLogRecord(name: name, timestamp: timestamp);

    final Future<void> inFlight = exporter.export(log('in.flight'));
    final Future<void> oldest = exporter.sendConfirmed(log('oldest'));
    final Future<void> older = exporter.export(log('older'));
    final Future<void> newer = exporter.export(log('newer'));
    final Future<void> newest = exporter.export(log('newest'));

    await expectLater(oldest, throwsStateError);
    release.complete();
    await Future.wait<void>(<Future<void>>[inFlight, older, newer, newest]);
    await exporter.shutdown();

    expect(delivered, <String>['in.flight', 'newer', 'newest']);
    expect(errors, hasLength(2));
    expect(errors, everyElement(isA<StateError>()));
  });

  test('rejects a backlog limit below one', () {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    expect(
      () => AtTelemetrySignedHttpExporter(
        endpoint: Uri.parse('http://localhost:4318'),
        serviceName: 'application',
        keyId: '@producer1',
        audience: 'localhost',
        signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
        maxQueuedExports: 0,
        client:
            MockClient((http.Request request) async => http.Response('', 200)),
      ),
      throwsRangeError,
    );
  });

  test('accepts a base or logs endpoint and always sends to /v1/logs',
      () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final DateTime timestamp = DateTime.utc(2026, 9, 29);
    for (final String path in <String>['', '/', '/v1/logs']) {
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
      await exporter
          .export(AtTelemetryLogRecord(name: 'lookup', timestamp: timestamp));
      await exporter.shutdown();
      expect(delivered, <String>['/v1/logs'], reason: path);
    }
  });

  test('rejects metrics and traces endpoints', () {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    for (final String path in <String>['/v1/metrics', '/v1/traces']) {
      expect(
        () => AtTelemetrySignedHttpExporter(
          endpoint: Uri.parse('http://localhost:4318$path'),
          serviceName: 'application',
          keyId: '@producer1',
          audience: 'localhost',
          signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
          client: MockClient(
              (http.Request request) async => http.Response('', 200)),
        ),
        throwsArgumentError,
        reason: path,
      );
    }
  });

  test('invalid log records are reported without sending HTTP', () async {
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
    await exporter.export(
        AtTelemetryLogRecord(name: ' ', timestamp: DateTime.utc(2026, 9, 29)));
    await exporter.shutdown();
    expect(errors, hasLength(1));
    expect(errors, everyElement(isA<ArgumentError>()));
    expect(requests, 0);
  });

  test('a rejected log is best effort and does not block later logs', () async {
    final RSAKeypair keys = RSAKeypair.fromRandom();
    final List<Object> errors = <Object>[];
    final List<String> names = <String>[];
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
        final String name = const AtTelemetryLogsCodec()
            .decodeExportRequest(request.bodyBytes)
            .single
            .name;
        names.add(name);
        return http.Response('', name == 'rejected' ? 401 : 200);
      }),
    );
    await exporter
        .export(AtTelemetryLogRecord(name: 'rejected', timestamp: timestamp));
    await exporter
        .export(AtTelemetryLogRecord(name: 'accepted', timestamp: timestamp));
    await exporter.shutdown();
    expect(errors, hasLength(1));
    expect(names, <String>['rejected', 'accepted']);
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
