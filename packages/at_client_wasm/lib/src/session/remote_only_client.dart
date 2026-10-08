import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';

/// An [AtClient] for [atSign] holding no local replica: its storage writes
/// through an authenticated [RemoteSecondary] over [lookUps].
Future<AtClient> remoteOnlyClient({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtKeysIo keysIo,
  required AtLookUpFactory lookUps,
  required SecondaryAddressFinder secondaryAddressFinder,
}) async {
  final keys = await keysIo.read(atSign);
  return AtClientImpl.create(
    atSign,
    app,
    prefs,
    atKeysIo: keysIo,
    lookUps: lookUps,
    secondaryAddressFinder: secondaryAddressFinder,
    storage: RemoteOnlyAtClientStorage(
      atSign: atSign,
      closedByClient: true,
      remoteSecondary: RemoteSecondary(
        atSign,
        prefs,
        atKeysIo: keysIo,
        lookUps: lookUps,
        secondaryAddressFinder: secondaryAddressFinder,
        enrollmentId: keys.enrollmentToAuthenticateAs(),
      ),
    ),
  );
}
