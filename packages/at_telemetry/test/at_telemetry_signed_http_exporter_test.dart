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
      attributes: <String, Object?>{'atsign.server.id': '@producer1'},
    ));
    await exporter.shutdown();
    expect(requests, 2);
  });
}
