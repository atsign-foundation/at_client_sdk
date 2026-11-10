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
/// [RemoteSecondary] alongside the client. [openLocalRecords] opens the
/// store for the `local:` records, given the enrollment the keys
/// authenticate as; without it those records stay in memory.
Future<({AtClient client, RemoteSecondary remote})> remoteOnlyClient({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtKeysIo keysIo,
  required AtLookUpFactory lookUps,
  required SecondaryAddressFinder secondaryAddressFinder,
  Future<LocalRecordStore> Function(String enrollmentId)? openLocalRecords,
}) async {
  final keys = await keysIo.read(atSign);
  final enrollmentId = keys.enrollmentToAuthenticateAs();
  final remote = RemoteSecondary(atSign, prefs,
      atKeysIo: keysIo,
      lookUps: lookUps,
      secondaryAddressFinder: secondaryAddressFinder,
      enrollmentId: enrollmentId);
  final storage = RemoteOnlyAtClientStorage(
      atSign: atSign,
      remoteSecondary: remote,
      closedByClient: true,
      localRecordStore: await openLocalRecords?.call(enrollmentId));
  final AtClientImpl client;
  try {
    client = (await AtClientImpl.create(
      atSign,
      app,
      prefs,
      atKeysIo: keysIo,
      lookUps: lookUps,
      secondaryAddressFinder: secondaryAddressFinder,
      remoteSecondary: remote,
      storage: storage,
    )) as AtClientImpl;
  } catch (_) {
    await storage.close();
    rethrow;
  }
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
