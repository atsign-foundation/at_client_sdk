import 'package:at_client/at_client.dart';

import 'remote_only_client.dart';

/// Starts a Mode E client from [atKeys]: remote-only over [lookUps], keys in
/// a fresh [InMemoryAtKeysIo] per call, nothing written to the device or the
/// server copy.
Future<AtClient> ephemeralSession({
  required String atSign,
  required String app,
  required AtKeys atKeys,
  required AtClientPreference prefs,
  required AtLookUpFactory lookUps,
}) async =>
    (await remoteOnlyClient(
            atSign: atSign,
            app: app,
            prefs: prefs,
            keysIo: InMemoryAtKeysIo.holding(atSign, atKeys),
            lookUps: lookUps))
        .client;
