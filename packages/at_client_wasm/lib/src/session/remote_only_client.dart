import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';

/// An [AtClient] for [atSign] holding no local replica: its storage writes
/// through the client's own authenticated [RemoteSecondary] over [lookUps],
/// so the client's stop closes the one connection both use.
Future<AtClient> remoteOnlyClient({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtKeysIo keysIo,
  required AtLookUpFactory lookUps,
  required SecondaryAddressFinder secondaryAddressFinder,
}) async {
  final keys = await keysIo.read(atSign);
  final remote = RemoteSecondary(atSign, prefs,
      atKeysIo: keysIo,
      lookUps: lookUps,
      secondaryAddressFinder: secondaryAddressFinder,
      enrollmentId: keys.enrollmentToAuthenticateAs());
  return AtClientImpl.create(
    atSign,
    app,
    prefs,
    atKeysIo: keysIo,
    lookUps: lookUps,
    secondaryAddressFinder: secondaryAddressFinder,
    remoteSecondary: remote,
    storage: RemoteOnlyAtClientStorage(
        atSign: atSign, remoteSecondary: remote, closedByClient: true),
  );
}
