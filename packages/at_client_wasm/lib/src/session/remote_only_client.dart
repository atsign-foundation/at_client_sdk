import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
// ignore: implementation_imports
import 'package:at_client/src/client/remote_secondary.dart';

/// An [AtClient] for [atSign] holding no local replica: its storage writes
/// through the client's own authenticated [RemoteSecondary] over [lookUps],
/// so the client's stop closes the one connection both use. Its notification
/// monitor connects over [lookUps] too. The connection and the notification
/// service resolve atSigns with [secondaryAddressFinder]. A start that fails once the client
/// is built stops it, so a retry builds afresh. Returns that
/// [RemoteSecondary] alongside the client.
Future<({AtClient client, RemoteSecondary remote})> remoteOnlyClient({
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
  final client = (await AtClientImpl.create(
    atSign,
    app,
    prefs,
    atKeysIo: keysIo,
    lookUps: lookUps,
    secondaryAddressFinder: secondaryAddressFinder,
    remoteSecondary: remote,
    storage: RemoteOnlyAtClientStorage(
        atSign: atSign, remoteSecondary: remote, closedByClient: true),
  )) as AtClientImpl;
  try {
    client.notificationService = await NotificationServiceImpl.create(client,
        connection: client.connection,
        lookUps: lookUps,
        secondaryAddressFinder: secondaryAddressFinder);
  } catch (_) {
    await client.stop();
    rethrow;
  }
  return (client: client, remote: remote);
}
