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

final _keyFileName = RegExp(r'(?:^|[/\\])(@[^/\\]+)_key\.atKeys$');

/// The atSign to cut for: [explicit], else the one [keys] names, else the
/// `@x_key.atKeys` convention in [atKeysPath]; null when none applies.
///
/// Throws [ArgumentError] when [explicit] contradicts the atSign [keys] names.
Atsign? resolveAtSign(AtKeys keys, String atKeysPath, {String? explicit}) {
  final named = keys.atsign;
  if (explicit != null) {
    final atSign = Atsign(explicit);
    if (named != null && named != atSign) {
      throw ArgumentError.value(
          explicit, 'explicit', 'keyfile belongs to $named');
    }
    return atSign;
  }
  if (named != null) return named;
  final match = _keyFileName.firstMatch(atKeysPath);
  return match == null ? null : Atsign(match.group(1)!);
}
