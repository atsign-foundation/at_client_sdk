// `AtPkamKeyPair` is deprecated in the current at_chops and is what 3.14.0's
// `AtChopsKeys.create` takes, so the deprecated spelling is the only one a
// released arm has.
// ignore_for_file: deprecated_member_use

/// How a released at_client's arm attaches a client with no key source.
///
/// Imported only by the released arms' programs: this tree's at_client takes
/// no `AtChops`, so nothing compiled against it may import this library.
library;

import 'package:at_chops/at_chops.dart'
    show
        AESKey,
        AtChops,
        AtChopsImpl,
        AtChopsKeys,
        AtEncryptionKeyPair,
        AtPkamKeyPair;
import 'package:at_client/at_client.dart'
    show AtClientManager, AtClientPreference;
import 'package:at_demo_data/at_demo_data.dart'
    show
        aesKeyMap,
        encryptionPrivateKeyMap,
        encryptionPublicKeyMap,
        pkamPrivateKeyMap,
        pkamPublicKeyMap;

import 'src/connect.dart' show ClientSpec;

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

/// Attaches [spec]'s client with no key source, handing it [demoAtChops].
///
/// A released at_client's keyless client signs with the AtChops it builds
/// from its local store at start, and that store is empty until the demo keys
/// are installed, so the arm injects one holding them.
Future<AtClientManager> attachWithDemoAtChops(
        ClientSpec spec, AtClientPreference preference) =>
    AtClientManager(spec.atSign).setCurrentAtSign(
        spec.atSign, spec.namespace, preference,
        atChops: demoAtChops(spec.atSign));
