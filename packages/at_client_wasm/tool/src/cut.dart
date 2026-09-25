import 'dart:convert';
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

/// The atProtocol key the envelope is published under, without the `public:` scope:
/// `_atkeys.<app>@<atsign>` (atSign normalised with a leading @). ArgumentError when [app]
/// is empty or contains ':', '@', whitespace or '.'-leading/trailing.
String atKeysRecordKey(String atSign, String app) {
  if (app.isEmpty ||
      app.contains(':') ||
      app.contains('@') ||
      app.contains(RegExp(r'\s')) ||
      app.startsWith('.') ||
      app.endsWith('.')) {
    throw ArgumentError.value(app, 'app', 'invalid app namespace');
  }
  return '_atkeys.$app${Atsign(atSign)}';
}

/// `update:public:<atKeysRecordKey> <envelope as UTF-8 text>\n`
String updateCommand(String atSign, String app, Uint8List envelope) {
  final recordKey = atKeysRecordKey(atSign, app);
  final envelopeText = utf8.decode(envelope);
  if (envelopeText.contains('\n')) {
    throw StateError('Envelope must not contain newlines');
  }
  return 'update:public:$recordKey $envelopeText\n';
}
