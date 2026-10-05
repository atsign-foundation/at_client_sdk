import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_telemetry/at_telemetry.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  const String producer = '@producer';
  const String collector = '@collector';
  const AtTelemetryLogsCodec codec = AtTelemetryLogsCodec();

  late RsaKeyPair producerKeys;
  late RsaKeyPair strangerKeys;
  late HttpServer server;
  late Set<String> seenNonces;
  late List<AtTelemetryLogRecord> received;
  late Map<String, String> lastHeaders;
  late List<int> lastBody;

  setUpAll(() {
    producerKeys = RsaKeyPair.generate();
    strangerKeys = RsaKeyPair.generate();
  });

  Future<void> reply(HttpRequest request, int statusCode,
      [List<int> body = const <int>[]]) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType('application', 'x-protobuf')
      ..add(body);
    await request.response.close();
  }

  Future<void> handle(HttpRequest request) async {
    final List<int> body = await request.fold<List<int>>(
      <int>[],
      (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
    );
    lastBody = body;
    lastHeaders = <String, String>{
      for (final String name in <String>[
        'content-type',
        AtTelemetryHttpSignature.inputHeader,
        AtTelemetryHttpSignature.signatureHeader,
        AtTelemetryHttpSignature.digestHeader,
        AtTelemetryHttpSignature.audienceHeader,
      ])
        name: request.headers.value(name) ?? '',
    };

    final AtTelemetryHttpSignature signature;
    try {
      signature = AtTelemetryHttpSignature.parse(
        input: lastHeaders[AtTelemetryHttpSignature.inputHeader]!,
        signature: lastHeaders[AtTelemetryHttpSignature.signatureHeader]!,
        digest: lastHeaders[AtTelemetryHttpSignature.digestHeader]!,
        audience: lastHeaders[AtTelemetryHttpSignature.audienceHeader]!,
      );
    } on FormatException {
      return reply(request, HttpStatus.badRequest);
    } on ArgumentError {
      return reply(request, HttpStatus.badRequest);
    }

    final bool accepted = request.method == 'POST' &&
        signature.keyId == producer &&
        signature.audience ==
            AtTelemetryHttpSignature.encodeAtsign(collector) &&
        signature.isFresh(DateTime.now()) &&
        signature.matchesBody(body) &&
        await signature.verify(
          path: request.uri.path,
          publicKey: producerKeys.atPublicKey.publicKey,
        ) &&
        seenNonces.add(signature.nonce);
    if (!accepted) {
      return reply(request, HttpStatus.unauthorized);
    }

    received.addAll(codec.decodeExportRequest(body));
    return reply(request, HttpStatus.ok, codec.encodeExportResponse());
  }

  setUp(() async {
    seenNonces = <String>{};
    received = <AtTelemetryLogRecord>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  AtTelemetry telemetryFor(RsaKeyPair keys, List<Object> errors) {
    return AtTelemetry(
      serviceName: 'my_app',
      resourceAttributes: const <String, Object?>{
        AtTelemetryHttpSignature.serverIdAttribute: producer,
      },
      exporter: AtTelemetrySignedHttpExporter(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        keyId: producer,
        audience: collector,
        signer: AtTelemetryRsaSigner.fromBase64(keys.atPrivateKey.privateKey),
      ),
      onError: (Object error, StackTrace _) => errors.add(error),
    );
  }

  group('signed HTTP telemetry end to end', () {
    test('the collector verifies and decodes an event', () async {
      final List<Object> errors = <Object>[];
      final AtTelemetry telemetry = telemetryFor(producerKeys, errors);
      final DateTime timestamp = DateTime.utc(2024, 1, 2, 3, 4, 5);

      telemetry.event(
        'atsign.server.heartbeat',
        attributes: const <String, Object?>{'uptime': 42},
        severity: AtTelemetrySeverity.info,
        timestamp: timestamp,
      );
      await telemetry.shutdown();

      expect(errors, isEmpty);
      final AtTelemetryLogRecord event = received.single;
      expect(event.eventName, 'atsign.server.heartbeat');
      expect(event.severityNumber, AtTelemetrySeverity.info);
      expect(event.timestamp, timestamp);
      expect(event.attributes, <String, Object?>{
        'uptime': 42,
        AtTelemetryResource.serviceNameAttribute: 'my_app',
        AtTelemetryHttpSignature.serverIdAttribute: producer,
      });
    });

    test('a record signed with the wrong key is reported to onError', () async {
      final List<Object> errors = <Object>[];
      final AtTelemetry telemetry = telemetryFor(strangerKeys, errors);

      telemetry.event('atsign.server.heartbeat');
      await telemetry.shutdown();

      expect(received, isEmpty);
      expect(
        errors.single,
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('HTTP 401'),
        ),
      );
    });

    test('a replayed request is rejected', () async {
      final List<Object> errors = <Object>[];
      final AtTelemetry telemetry = telemetryFor(producerKeys, errors);
      telemetry.event('atsign.server.heartbeat');
      await telemetry.shutdown();
      expect(received, hasLength(1));

      final Uri url = Uri.parse('http://127.0.0.1:${server.port}/v1/logs');
      final Map<String, String> headers = lastHeaders;
      final List<int> body = lastBody;

      final http.Response replayed =
          await http.post(url, headers: headers, body: body);
      expect(replayed.statusCode, HttpStatus.unauthorized);
      expect(received, hasLength(1));

      seenNonces.clear();
      final http.Response forgotten =
          await http.post(url, headers: headers, body: body);
      expect(forgotten.statusCode, HttpStatus.ok);
      expect(received, hasLength(2));
    });
  });
}
