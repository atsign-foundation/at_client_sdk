import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/ml_dsa_keyfile.dart';

/// `LocalSecondary`'s key getters resolve across two tiers: the client's key
/// source, then the keystore.
///
/// The key source is what lets a client take its key material from an
/// `AtKeysIo` — the non-deprecated way to hand a client its keys — rather
/// than from an `AtChops` somebody built for it. The PKAM getters reach it
/// through `authenticationKeyPairFor`, which refuses a keypair filed under an
/// algorithm this build cannot sign with, and that refusal is not fallen
/// through to the keystore.
void main() {
  const atSign = '@alice🛠';
  const enrollmentId = 'test-enrollment';

  AtClientPreference prefs() => AtClientPreference()
    ..namespace = 'unit'
    ..rootDomain = 'test.atsign.wtf';

  Future<AtClient> clientWith({required InMemoryAtKeysIo? keySource}) async =>
      AtClientImpl.create(atSign, 'unit', prefs(),
          remoteSecondary: MockRemoteSecondary(),
          storage:
              InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
          atKeysIo: keySource);

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  test('the key source answers the encryption material', () async {
    final local = (await clientWith(keySource: await typedKeyfile(atSign)))
        .getLocalSecondary()!;

    expect(await local.getEncryptionSelfKey(), testSelfEncryptionKey);
    expect(await local.getEncryptionPublicKey(atSign), testEncryptionPublicKey);
    expect(await local.getEncryptionPrivateKey(), testEncryptionPrivateKey);
  });

  test("the key source answers the enrollment's APKAM keypair", () async {
    final local = (await clientWith(keySource: await typedKeyfile(atSign)))
        .getLocalSecondary()!;

    // The stand-in bytes typedKeyfile files, as AtBytes spells them.
    expect(
        await local.getPkamPrivateKey(), base64Encode(List<int>.filled(32, 3)));
    expect(
        await local.getPkamPublicKey(), base64Encode(List<int>.filled(32, 4)));
  });

  test(
      'a keypair under an algorithm this build cannot sign with is refused, '
      'not fallen through to the keystore', () async {
    // A LocalSecondary over a mock client, because a real client refuses such
    // a keyfile at construction and the getter would never be reached.
    final atClient = MockAtClientImpl();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);
    final refusing = await typedKeyfile(atSign,
        algorithm: CryptographicMaterialAlgorithm.of('sphincs-plus-256s'));
    when(() => atClient.atKeysIo).thenReturn(refusing);
    final storage = InMemoryAtClientStorage(atSign: atSign);
    await storage.attach(atClient);
    final local = LocalSecondary(atClient, keyStore: storage.keyStore);
    // The control: the keystore holds a keypair, so a getter that fell
    // through the refusal would answer this rather than throw.
    await local.putValue(AtConstants.atPkamPrivateKey, 'keystore-private');
    await local.putValue(AtConstants.atPkamPublicKey, 'keystore-public');

    await expectLater(() => local.getPkamPrivateKey(),
        throwsA(isA<AtKeyNotFoundException>()));
    await expectLater(
        () => local.getPkamPublicKey(), throwsA(isA<AtKeyNotFoundException>()));
    await storage.close();
  });

  test('control: with no key source the read falls through to the keystore',
      () async {
    // The keystore is empty, so every tier misses and the last one throws —
    // which is what the legacy self-key path catches. Without this arm the
    // tests above would pass on a getter that answered from anywhere at all.
    final local = (await clientWith(keySource: null)).getLocalSecondary()!;

    await expectLater(() => local.getEncryptionSelfKey(),
        throwsA(isA<KeyNotFoundException>()));
    await expectLater(() => local.getEncryptionPublicKey(atSign),
        throwsA(isA<KeyNotFoundException>()));
    await expectLater(() => local.getEncryptionPrivateKey(),
        throwsA(isA<KeyNotFoundException>()));
    await expectLater(
        () => local.getPkamPrivateKey(), throwsA(isA<KeyNotFoundException>()));
  });
}
