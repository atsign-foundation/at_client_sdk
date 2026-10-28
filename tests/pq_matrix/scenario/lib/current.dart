/// How this tree's arm attaches a client with no key source.
///
/// Imported only by programs compiled against this tree: a released at_client
/// has neither `buildAtClient` nor `AtClientManager.use`, so no released arm
/// may import this library.
library;

import 'package:at_client/at_client.dart'
    show AtClientManager, AtClientPreference, buildAtClient;
import 'package:at_client/hive.dart' show HiveAtClientStorage;
import 'package:at_demo_data/at_demo_data.dart' show pkamPrivateKeyMap;

import 'src/connect.dart' show ClientSpec;

/// This tree's attach with no key source: [preference] is given the demo
/// atSign's PKAM private key, which this tree's keyless client signs with,
/// and the client opens the Hive store under the spec's storage path.
///
/// A released arm attaches with `released.dart`'s `attachWithDemoAtChops`
/// instead, and an arm needing an `AtKeysIo` supplies its own.
Future<AtClientManager> attachWithoutKeySource(
    ClientSpec spec, AtClientPreference preference) async {
  final client = await buildAtClient(
      atSign: spec.atSign,
      namespace: spec.namespace,
      preference: preference..privateKey = pkamPrivateKeyMap[spec.atSign],
      storage: HiveAtClientStorage(
          atSign: spec.atSign,
          storagePath: spec.storagePath,
          closedByClient: true));
  return AtClientManager(spec.atSign)..use(client);
}
