import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryRsaSigner', () {
    late RsaKeyPair keys;

    setUpAll(() {
      keys = RsaKeyPair.generate();
    });

    test('produces a 256 byte signature that verifies', () async {
      final List<int> message = utf8.encode('hello');
      final AtTelemetryRsaSigner signer =
          AtTelemetryRsaSigner.fromBase64(keys.atPrivateKey.privateKey);

      final Uint8List signature = await signer.sign(message);

      expect(signature, hasLength(256));
      expect(
        await RsaSignatureAlgo.rsa2048().verifyBytes(
          Uint8List.fromList(message),
          signature: signature,
          publicKey: base64Decode(keys.atPublicKey.publicKey),
        ),
        isTrue,
      );
    });

    test('fromBase64 rejects a string that is not base64', () {
      expect(
        () => AtTelemetryRsaSigner.fromBase64('not base64!'),
        throwsFormatException,
      );
    });
  });
}
