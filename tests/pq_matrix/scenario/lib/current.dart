/// How this tree's arm attaches a client.
///
/// Imported only by programs compiled against this tree: a released at_client
/// has neither `buildAtClient` nor `AtClientManager.use`, so no released arm
/// may import this library.
library;

import 'package:at_client/at_client.dart'
    show
        AtClientManager,
        AtClientPreference,
        AtKeys,
        InMemoryAtKeysIo,
        buildAtClient;
import 'package:at_client/hive.dart' show HiveAtClientStorage;
import 'package:at_demo_data/at_demo_data.dart'
    show
        aesKeyMap,
        encryptionPrivateKeyMap,
        encryptionPublicKeyMap,
        pkamPrivateKeyMap,
        pkamPublicKeyMap;

import 'src/connect.dart' show ClientSpec;

/// This tree's attach: the client holds the demo atSign's keys as a legacy
/// keyfile holds them, and opens the Hive store under the spec's storage
/// path.
///
/// A released arm attaches with `released.dart`'s `attachWithDemoAtChops`
/// instead.
Future<AtClientManager> attachWithDemoKeys(
    ClientSpec spec, AtClientPreference preference) async {
  final atSign = spec.atSign;
  // NOTE: flat, never typed. Typed rsa2048 authentication material reads as
  // a retrofit already done.
  final keys = AtKeys.legacy(
    apkamPublicKey: pkamPublicKeyMap[atSign]!,
    apkamPrivateKey: pkamPrivateKeyMap[atSign]!,
    encryptionPublicKey: encryptionPublicKeyMap[atSign]!,
    encryptionPrivateKey: encryptionPrivateKeyMap[atSign]!,
    selfEncryptionKey: aesKeyMap[atSign]!,
  );
  final client = await buildAtClient(
      atSign: atSign,
      namespace: spec.namespace,
      preference: preference,
      atKeysIo: InMemoryAtKeysIo.holding(atSign, keys),
      storage: HiveAtClientStorage(
          atSign: atSign, storagePath: spec.storagePath, closedByClient: true));
  return AtClientManager(atSign)..use(client);
}
