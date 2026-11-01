import 'package:at_chops/at_chops.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todos/onboarding.dart';

/// Catalogue: features/at_client_flutter/todos_logout.feature
void main() {
  const atSign = '@todos';

  /// A key set for [atSign] the client can open on: it opens offline, since
  /// the atDirectory is a closed local port.
  Future<InMemoryAtKeysIo> keys() async {
    final encryption = RsaKeyPair.generate();
    final apkam = RsaKeyPair.generate();
    // ignore: invalid_use_of_visible_for_testing_member
    final io = InMemoryAtKeysIo();
    await io.write(
      atSign,
      AtKeys.legacy(
        apkamPublicKey: apkam.atPublicKey.publicKey,
        apkamPrivateKey: apkam.atPrivateKey.privateKey,
        encryptionPublicKey: encryption.atPublicKey.publicKey,
        encryptionPrivateKey: encryption.atPrivateKey.privateKey,
        selfEncryptionKey: AESKey.generate(32).key,
      ),
    );
    return io;
  }

  Future<AtClient> signIn(AtKeysIo keys) => Atsign(atSign).open(
    keys: keys,
    preference: AtClientPreference()..namespace = 'todos',
    storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
    lookUps: secureSocketLookUps(),
    secondaryAddressFinder: FixedSecondaryAddressFinder('127.0.0.1', 1),
    connectBudget: const Duration(seconds: 2),
  );

  test(
    'Logging out stops the client, so the same atSign can sign in again',
    () async {
      final io = await keys();
      final client = await signIn(io);
      AtClientManager.getInstance().use(client);

      await logout();

      expect(client.isStopped, isTrue);
      expect(() => AtClientManager.getInstance().atClient, throwsStateError);
      final again = await signIn(io);
      addTearDown(again.stop);
      expect(again.isStopped, isFalse);
    },
  );
}
