import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';

import '../keys/key_bytes_store.dart';
import '../keys/key_envelope.dart';
import '../keys/passkey_kek.dart';
import '../keys/unlock_secret.dart';
import 'key_acquisition.dart';
import 'remote_only_client.dart';
import 'server_copy.dart';

final _logger = AtSignLogger('portalSession');

/// Starts a Mode P client: keys from [acquireKeys], storage remote-only over
/// [lookUps], then [heal] when the keys are passkey-held. A failed heal is
/// logged and leaves the client running.
Future<AtClient> portalSession({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtLookUpFactory lookUps,
  required KeyBytesStore store,
  required PasskeyKek kek,
  required ServerCopy server,
  required Future<PassphraseSecret> Function(String atSign) promptPassphrase,
  KeyEnvelopeCodec codec = const KeyEnvelopeCodec(),
  CredentialHintStore? hintStore,
}) async {
  final keys = await acquireKeys(
    atSign: atSign,
    app: app,
    store: store,
    kek: kek,
    server: server,
    promptPassphrase: promptPassphrase,
    codec: codec,
    hintStore: hintStore,
  );
  final client = await remoteOnlyClient(
      atSign: atSign,
      app: app,
      prefs: prefs,
      keysIo: keys.keysIo,
      lookUps: lookUps);

  final prf = keys.prf;
  if (prf != null) {
    try {
      await heal(
          atSign: atSign,
          app: app,
          store: store,
          server: server,
          prf: prf,
          codec: codec);
    } on Exception catch (e) {
      _logger.warning('could not heal the server copy of $atSign\'s keys '
          'for $app: $e');
    }
  }
  return client;
}
