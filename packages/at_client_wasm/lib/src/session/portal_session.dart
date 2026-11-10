import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/client/remote_secondary.dart';

import '../keys/key_bytes_store.dart';
import '../keys/key_envelope.dart';
import '../keys/passkey_kek.dart';
import '../keys/unlock_secret.dart';
import 'key_acquisition.dart';
import 'lookup_server_copy.dart';
import 'remote_only_client.dart';
import 'server_copy.dart';

final _logger = AtSignLogger('portalSession');

/// Starts a Mode P client: keys from [acquireKeys], storage remote-only over
/// [lookUps], then [heal] when the keys are passkey-held. A failed heal is
/// logged and leaves the client running.
///
/// [server] reads the server copy, by default with an unauthenticated
/// lookup over [lookUps] at [prefs]' root. [healServer] gives [heal] its
/// server copy over the client's [RemoteSecondary], by default reading
/// through [server] and writing on that connection. atSigns resolve with
/// [secondaryAddressFinder], as [remoteOnlyClient] takes it.
Future<AtClient> portalSession({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtLookUpFactory lookUps,
  required SecondaryAddressFinder secondaryAddressFinder,
  required KeyBytesStore store,
  required PasskeyKek kek,
  ServerCopyReader? server,
  ServerCopy Function(RemoteSecondary remote)? healServer,
  required Future<PassphraseSecret> Function(String atSign) promptPassphrase,
  Future<AtKeys> Function(String atSign)? uploadAtKeys,
  KeyEnvelopeCodec codec = const KeyEnvelopeCodec(),
  CredentialHintStore? hintStore,
}) async {
  final reader = server ??
      LookupServerCopyReader(
          lookUps: lookUps,
          rootDomain: AtRootDomain(prefs.rootDomain, prefs.rootPort));
  final keys = await acquireKeys(
    atSign: atSign,
    app: app,
    store: store,
    kek: kek,
    server: reader,
    promptPassphrase: promptPassphrase,
    uploadAtKeys: uploadAtKeys,
    codec: codec,
    hintStore: hintStore,
  );
  final (:client, :remote) = await remoteOnlyClient(
      atSign: atSign,
      app: app,
      prefs: prefs,
      keysIo: keys.keysIo,
      lookUps: lookUps,
      secondaryAddressFinder: secondaryAddressFinder);

  final prf = keys.prf;
  if (prf != null) {
    try {
      final outcome = await heal(
          atSign: atSign,
          app: app,
          store: store,
          server: (healServer ?? (r) => RemoteServerCopy(reader, r))(remote),
          prf: prf,
          codec: codec);
      switch (outcome) {
        case HealOutcome.healed:
          _logger.info('added this device\'s passkey unlock to the server '
              'copy of $atSign\'s keys for $app');
        case HealOutcome.alreadyPresent:
          break;
        case HealOutcome.contentKeyMismatch:
          _logger.warning('the server copy of $atSign\'s keys for $app is '
              'sealed under a different content key from this device\'s copy');
        case HealOutcome.missingCopy:
          _logger.severe('no device or server copy of $atSign\'s keys for '
              '$app after acquiring them');
      }
    } on Exception catch (e) {
      _logger.warning('could not heal the server copy of $atSign\'s keys '
          'for $app: $e');
    }
  }
  return client;
}
