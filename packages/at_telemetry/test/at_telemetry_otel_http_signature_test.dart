import 'dart:convert';

import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

void main() {
  final RSAKeypair keys = RSAKeypair.fromRandom();
  final DateTime now = DateTime.utc(2026, 9, 25, 12);
  final List<int> body = utf8.encode('hello telemetry');

  Future<AtTelemetryOtelHttpSignature> sign() =>
      AtTelemetryOtelHttpSignature.sign(
        body: body,
        path: '/v1/logs',
        keyId: '@Producer1',
        audience: '@telemetry1',
        signer: AtTelemetryRsaSigner.fromBase64(keys.privateKey.toString()),
        now: () => now,
      );

  test('signs and verifies an exact OTLP request', () async {
    final AtTelemetryOtelHttpSignature signed = await sign();
    final AtTelemetryOtelHttpSignature parsed =
        AtTelemetryOtelHttpSignature.parse(
      input: signed.input,
      signature: signed.signature,
      digest: signed.digest,
      audience: signed.audience,
    );
    expect(parsed.isFresh(now), isTrue);
    expect(parsed.matchesBody(body), isTrue);
    expect(parsed.matchesBody(utf8.encode('altered')), isFalse);
    expect(
        await parsed.verify(
          path: '/v1/logs',
          publicKey: keys.publicKey.toString(),
        ),
        isTrue);
    expect(
        await parsed.verify(
          path: '/other',
          publicKey: keys.publicKey.toString(),
        ),
        isFalse);
    expect(
        AtTelemetryOtelHttpSignature.signatureBase(
          path: '/v1/logs',
          digest: signed.digest,
          audience: signed.audience,
          input: signed.input,
        ),
        contains('\n'));
    expect(parsed.isFresh(now.add(const Duration(minutes: 6))), isFalse);
  });

  test('rejects malformed inputs and accepts encoded Atsigns', () async {
    final AtTelemetryOtelHttpSignature signed = await sign();
    expect(
        () => AtTelemetryOtelHttpSignature.parse(
              input: signed.input.replaceFirst('at-telemetry-v1', 'pol1'),
              signature: signed.signature,
              digest: signed.digest,
              audience: signed.audience,
            ),
        throwsFormatException);
    expect(
        AtTelemetryOtelHttpSignature.decodeAtsign(
          AtTelemetryOtelHttpSignature.encodeAtsign('@🦊'),
        ),
        '@🦊');
  });
}
