import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/ml_dsa_keyfile.dart';

/// `LocalSecondary`'s key getters resolve across three tiers: an injected
/// `AtChops`, then the client's key source, then the keystore.
///
/// The middle tier is what lets a client take its key material from an
/// `AtKeysIo` — the non-deprecated way to hand a client its keys — rather than
/// from an `AtChops` somebody built for it.
void main() {
  const atSign = '@alice🛠';

  AtClientPreference prefs() => AtClientPreference()
    ..namespace = 'unit'
    ..rootDomain = 'test.atsign.wtf';

  Future<AtClient> clientWith({
    required bool withKeySource,
    required bool withEmptyAtChops,
  }) async =>
      AtClientImpl.create(atSign, 'unit', prefs(),
          remoteSecondary: MockRemoteSecondary(),
          storage:
              InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
          // An AtChops carrying nothing, on purpose: with material in it the
          // first tier would answer and the key source would never be
          // consulted, so the test would pass without measuring anything.
          // ignore: deprecated_member_use
          atChops: withEmptyAtChops ? AtChopsImpl(AtChopsKeys()) : null,
          atKeysIo: withKeySource ? await typedKeyfile(atSign) : null);

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  test('the key source answers what an empty AtChops cannot', () async {
    final local =
        (await clientWith(withKeySource: true, withEmptyAtChops: true))
            .getLocalSecondary()!;

    expect(await local.getEncryptionSelfKey(), testSelfEncryptionKey);
    expect(await local.getEncryptionPublicKey(atSign), testEncryptionPublicKey);
    expect(await local.getEncryptionPrivateKey(), testEncryptionPrivateKey);
  });

  test('control: with no key source the read falls through to the keystore',
      () async {
    // The keystore is empty and the AtChops carries nothing, so every tier
    // misses and the last one throws — which is what the legacy self-key
    // path catches. Without this arm the test above would pass on a getter
    // that read the keystore, or one that answered from anywhere at all.
    final local =
        (await clientWith(withKeySource: false, withEmptyAtChops: true))
            .getLocalSecondary()!;

    await expectLater(() => local.getEncryptionSelfKey(),
        throwsA(isA<KeyNotFoundException>()));
    await expectLater(() => local.getEncryptionPublicKey(atSign),
        throwsA(isA<KeyNotFoundException>()));
    await expectLater(() => local.getEncryptionPrivateKey(),
        throwsA(isA<KeyNotFoundException>()));
  });
}
