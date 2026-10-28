import 'package:at_client/at_client.dart'
    show AtClient, AtClientManager, AtClientPreference;
import 'package:at_commons/at_commons.dart' show AtConstants;
import 'package:at_demo_data/at_demo_data.dart'
    show aesKeyMap, encryptionPrivateKeyMap, encryptionPublicKeyMap,
        pkamPrivateKeyMap, pkamPublicKeyMap;

/// Everything about a client that does **not** depend on which at_client is
/// resolved: which atSign, where its atServer is, where its storage goes.
///
/// The stage lives outside this on purpose: `PqPosture` does not exist in
/// 3.14.0, so a field naming one could not be in shared code at all.
class ClientSpec {
  final String atSign;
  final String namespace;
  final String rootDomain;
  final int rootPort;

  /// Per-run, per-atSign, per-stage: two cells sharing a Hive directory would
  /// have the second read the first's local records and pass without the
  /// atServer being involved at all.
  final String storagePath;

  /// The enrollment this client authenticates as, or null for a client whose
  /// keyfile names none (which signs and advertises under `primary`).
  final String? enrollmentId;

  const ClientSpec({
    required this.atSign,
    required this.namespace,
    required this.rootDomain,
    required this.rootPort,
    required this.storagePath,
    this.enrollmentId,
  });
}

/// How an arm attaches its client to the manager.
///
/// A callback rather than a branch because each at_client takes a keyless
/// client's credential differently: this tree's client takes no `AtChops`,
/// and a released one authenticates a keyless client only through one — and
/// an arm attached without a key source performs zero post-quantum writes by
/// design.
typedef Attach = Future<AtClientManager> Function(
    ClientSpec spec, AtClientPreference preference);

/// Installs the demo atSign's key material into the local keystore.
///
/// Without these records a client authenticates but cannot encrypt to anyone,
/// so every cell would fail at its first put for a reason having nothing to do
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
/// Each attach makes its own [AtClientManager] rather than using the
/// singleton, whose `setCurrentAtSign` in a released at_client stops
/// whichever client was current.
Future<AtClient> connect({
  required ClientSpec spec,
  required AtClientPreference preference,
  required Attach attach,
}) async {
  final manager = await attach(spec, preference);
  final client = manager.atClient;
  await installDemoKeys(client, spec.atSign);
  return client;
}
