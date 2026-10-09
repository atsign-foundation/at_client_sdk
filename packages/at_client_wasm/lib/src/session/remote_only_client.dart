import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';

/// An [AtClient] for [atSign] holding no local replica: its storage writes
/// through the client's own authenticated [RemoteSecondary] over [lookUps],
/// so the client's stop closes the one connection both use. Returns that
/// [RemoteSecondary] alongside the client.
Future<({AtClient client, RemoteSecondary remote})> remoteOnlyClient({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtKeysIo keysIo,
  required AtLookUpFactory lookUps,
}) async {
  final keys = await keysIo.read(atSign);
  final remote = RemoteSecondary(atSign, prefs,
      atKeysIo: keysIo,
      lookUps: lookUps,
      enrollmentId: keys.enrollmentToAuthenticateAs());
  final client = await AtClientImpl.create(
    atSign,
    app,
    prefs,
    atKeysIo: keysIo,
    lookUps: lookUps,
    remoteSecondary: remote,
    storage: RemoteOnlyAtClientStorage(
        atSign: atSign, remoteSecondary: remote, closedByClient: true),
  );
  return (client: client, remote: remote);
}
