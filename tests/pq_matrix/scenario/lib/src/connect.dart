// `AtPkamKeyPair` is deprecated in the current at_chops and is what 3.14.0's
// `AtChopsKeys.create` takes. The shared scenario has to compile against both,
// so the deprecated spelling is the only one available to it — this is exactly
// the intersection the library's contract describes.
// ignore_for_file: deprecated_member_use

import 'package:at_chops/at_chops.dart'
    show
        AESKey,
        AtChops,
        AtChopsImpl,
        AtChopsKeys,
        AtEncryptionKeyPair,
        AtPkamKeyPair;
import 'package:at_client/at_client.dart'
    show AtClient, AtClientManager, AtClientPreference;
import 'package:at_commons/at_commons.dart' show AtConstants;
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap, encryptionPublicKeyMap,
        pkamPrivateKeyMap, pkamPublicKeyMap;

/// Everything about a client that does **not** depend on which at_client is
/// resolved: which atSign, where its atServer is, where its storage goes.
///
/// The stage lives outside this on purpose. `SigningRollout` does not exist in
/// 3.14.0, so a field naming one could not be in shared code at all — which is
/// the constraint that keeps the two arms honest rather than an inconvenience.
class ClientSpec {
  final String atSign;
  final String namespace;
  final String rootDomain;
  final int rootPort;

  /// Per-run, per-atSign, per-stage. Two cells of the matrix sharing a Hive
  /// directory would have the second read the first's local records and pass
  /// without the atServer being involved at all.
  final String storagePath;

  const ClientSpec({
    required this.atSign,
    required this.namespace,
    required this.rootDomain,
    required this.rootPort,
    required this.storagePath,
  });
}

/// How an arm attaches its client to the manager.
///
/// This is the **one** version-specific step, and it is a callback rather than
/// a branch because the difference is not expressible in shared code: the
/// current tree's `setCurrentAtSign` takes an `AtKeysIo` and 3.14.0's does
/// not. It matters far more than its size suggests — a client with no key
/// source performs zero post-quantum writes by design, so a `rollout2` arm
/// attached without one would mint nothing and the whole stage would measure
/// an inert client.
typedef Attach = Future<AtClientManager> Function(
    ClientSpec spec, AtClientPreference preference, AtChops atChops);

/// The AtChops a demo atSign authenticates with.
///
/// The virtualenv's `pkamLoad` installs these atSigns' PKAM public keys, so
/// this is the key material that atServer already trusts.
AtChops demoAtChops(String atSign) {
  final keys = AtChopsKeys.create(
    AtEncryptionKeyPair.create(
        encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!),
    AtPkamKeyPair.create(
        pkamPublicKeyMap[atSign]!, pkamPrivateKeyMap[atSign]!),
  );
  keys.selfEncryptionKey = AESKey(aesKeyMap[atSign]!);
  return AtChopsImpl(keys);
}

/// Installs the demo atSign's key material into the local keystore.
///
/// The same five records the functional pack's `AtEncryptionKeysLoader`
/// installs. Without them a client authenticates but cannot encrypt to anyone,
/// so every cell would fail at the first put for a reason having nothing to do
/// with the stage under test.
Future<void> installDemoKeys(AtClient client, String atSign) async {
  final local = client.getLocalSecondary()!;
  await local.putValue(
      AtConstants.atEncryptionPrivateKey, encryptionPrivateKeyMap[atSign]!);
  await local.putValue('${AtConstants.atEncryptionPublicKey}$atSign',
      encryptionPublicKeyMap[atSign]!);
  await local.putValue(AtConstants.atEncryptionSelfKey, aesKeyMap[atSign]!);
  await local.putValue(
      AtConstants.atPkamPublicKey, pkamPublicKeyMap[atSign]!);
  await local.putValue(
      AtConstants.atPkamPrivateKey, pkamPrivateKeyMap[atSign]!);
}

/// Brings up a client for [spec] under [preference], attached by [attach].
///
/// Its own [AtClientManager] rather than the singleton: a matrix cell runs a
/// sender and a receiver as two processes, but nothing here should depend on
/// that, and `getInstance().setCurrentAtSign` stops whichever client was
/// current.
Future<AtClient> connect({
  required ClientSpec spec,
  required AtClientPreference preference,
  required Attach attach,
}) async {
  final manager = await attach(spec, preference, demoAtChops(spec.atSign));
  final client = manager.atClient;
  await installDemoKeys(client, spec.atSign);
  return client;
}

/// The default attach: what compiles against **both** at_clients.
///
/// The published arm uses this unchanged. The current arm supplies its own,
/// adding the `AtKeysIo` that 3.14.0 has no parameter for.
Future<AtClientManager> attachWithoutKeySource(
        ClientSpec spec, AtClientPreference preference, AtChops atChops) =>
    AtClientManager(spec.atSign)
        .setCurrentAtSign(spec.atSign, spec.namespace, preference,
            atChops: atChops);
