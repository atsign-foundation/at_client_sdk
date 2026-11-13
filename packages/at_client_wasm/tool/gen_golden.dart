import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client_wasm/src/keys/key_envelope.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';

void main() async {
  final codec = KeyEnvelopeCodec(
    passphraseParams: Pbkdf2Sha256Params(iterations: 1000),
  );

  final plaintext = {
    "atSign": "@golden",
    "note": "at_client_wasm envelope v1 golden"
  };

  final secrets = [
    PrfSecret(Uint8List.fromList(List.generate(32, (i) => i))),
    PassphraseSecret('golden-passphrase-not-secret'),
  ];

  final envelope = await codec.seal('@golden', plaintext, secrets);

  final file = File('test/fixtures/envelope_v1_golden.json');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(envelope);
}
