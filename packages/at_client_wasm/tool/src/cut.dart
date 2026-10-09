import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_wasm/src/keys/key_envelope.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_commons/at_commons.dart';

/// Seals [keys] for its atSign with a freshly generated passphrase as the only unlock.
Future<({Uint8List envelope, PassphraseSecret passphrase})> cutEnvelope(
    AtKeys keys,
    {KeyEnvelopeCodec codec = const KeyEnvelopeCodec()}) async {
  final atSign = keys.atsign;
  if (atSign == null) {
    throw ArgumentError('AtKeys must have an atsign');
  }
  final atSignStr = Atsign(atSign).toString();
  final passphrase = PassphraseSecret.generate();
  final plaintext = keys.toJson();
  final envelope = await codec.seal(atSignStr, plaintext, [passphrase]);
  return (envelope: envelope, passphrase: passphrase);
}
