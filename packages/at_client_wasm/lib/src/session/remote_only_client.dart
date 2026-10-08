import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';

/// An [AtClient] for [atSign] holding no local replica: its storage writes
/// through an authenticated [RemoteSecondary] over [lookUps].
///
/// Sets [prefs]' `isLocalStoreRequired` to false, which turns off the
/// client's expiry and availability timers over a local replica.
Future<AtClient> remoteOnlyClient({
  required String atSign,
  required String app,
  required AtClientPreference prefs,
  required AtKeysIo keysIo,
  required AtLookUpFactory lookUps,
}) async {
  final keys = await keysIo.read(atSign);
  // ignore: deprecated_member_use
  prefs.isLocalStoreRequired = false;
  return AtClientImpl.create(
    atSign,
    app,
    prefs,
    atKeysIo: keysIo,
    lookUps: lookUps,
    storage: RemoteOnlyAtClientStorage(
      atSign: atSign,
      closedByClient: true,
      remoteSecondary: RemoteSecondary(
        atSign,
        prefs,
        atKeysIo: keysIo,
        lookUps: lookUps,
        enrollmentId: keys.enrollmentToAuthenticateAs(),
      ),
    ),
  );
}
