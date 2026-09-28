import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';

// Run with: dart run example/otel_signed_http_exporter_example.dart
//
// A producer (@producer) signs each OTLP request with its RSA private key.
// A local collector (@collector) verifies the signature against the
// producer's public key before accepting the events.
const String producer = '@producer';
const String collector = '@collector';

Future<void> main() async {
  // In production these are the producer's own keys, and the collector looks
  // up the producer's public key, for example from its atServer
  final RsaKeyPair keys = RsaKeyPair.generate();
  final Map<String, String> publicKeys = <String, String>{
    producer: keys.atPublicKey.publicKey,
  };

  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final Set<String> seenNonces = <String>{};
  server.listen(
    (HttpRequest request) => _handle(request, publicKeys, seenNonces),
  );

  final AtTelemetryOtelSignedHttpExporter exporter =
      AtTelemetryOtelSignedHttpExporter(
    endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
    serviceName: 'my_app',
    keyId: producer,
    audience: collector,
    signer: AtTelemetryOtelRsaSigner.fromBase64(keys.atPrivateKey.privateKey),
    // Send failures are only reported here, export() does not throw them
    onError: (Object error) => print('Telemetry failed: $error'),
  );

  await exporter.export(AtTelemetryEvent(
    name: 'atsign.server.heartbeat',
    timestamp: DateTime.now().toUtc(),
    attributes: const <String, Object?>{
      AtTelemetryOtelHttpSignature.serverIdAttribute: producer,
    },
  ));
  await exporter.shutdown();
  await server.close(force: true);
}

Future<void> _handle(
  HttpRequest request,
  Map<String, String> publicKeys,
  Set<String> seenNonces,
) async {
  final List<int> body = await request.fold<List<int>>(
    <int>[],
    (List<int> bytes, List<int> chunk) => bytes..addAll(chunk),
  );

  final AtTelemetryOtelHttpSignature signature;
  try {
    signature = AtTelemetryOtelHttpSignature.parse(
      input:
          request.headers.value(AtTelemetryOtelHttpSignature.inputHeader) ?? '',
      signature:
          request.headers.value(AtTelemetryOtelHttpSignature.signatureHeader) ??
              '',
      digest:
          request.headers.value(AtTelemetryOtelHttpSignature.digestHeader) ??
              '',
      audience:
          request.headers.value(AtTelemetryOtelHttpSignature.audienceHeader) ??
              '',
    );
  } on FormatException {
    return _reply(request, HttpStatus.badRequest);
  } on ArgumentError {
    return _reply(request, HttpStatus.badRequest);
  }

  final String? publicKey = publicKeys[signature.keyId];
  final bool accepted = request.method == 'POST' &&
      signature.audience ==
          AtTelemetryOtelHttpSignature.encodeAtsign(collector) &&
      signature.isFresh(DateTime.now()) &&
      signature.matchesBody(body) &&
      publicKey != null &&
      await signature.verify(path: request.uri.path, publicKey: publicKey) &&
      seenNonces.add(signature.nonce);
  if (!accepted) {
    return _reply(request, HttpStatus.unauthorized);
  }

  const AtTelemetryOtelLogsCodec codec = AtTelemetryOtelLogsCodec();
  for (final AtTelemetryEvent event in codec.decodeExportRequest(body)) {
    print('Verified event from ${signature.keyId}: '
        '${event.name} ${event.attributes}');
  }
  return _reply(request, HttpStatus.ok, codec.encodeExportResponse());
}

Future<void> _reply(
  HttpRequest request,
  int statusCode, [
  List<int> body = const <int>[],
]) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType('application', 'x-protobuf')
    ..add(body);
  await request.response.close();
}
