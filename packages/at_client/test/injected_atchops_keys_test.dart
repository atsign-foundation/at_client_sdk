// A client handed an AtChops and no key source is the shape under test, so
// this file names the AtChops on purpose.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/ml_dsa_keyfile.dart';

/// A client built with an AtChops and no key source reads its keys from that
/// AtChops when neither the key source nor the keystore holds them.
void main() {
  const atSign = '@chopsonly';
  late Directory dir;
  late AtEncryptionKeyPair encryptionKeyPair;
  late AtPkamKeyPair pkamKeyPair;
  late SymmetricKey selfEncryptionKey;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('injected_atchops_');
    encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    selfEncryptionKey = AESKey.generate(32);
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<AtClient> clientHolding(AtChopsKeys keys) async {
    final client = await AtClientImpl.create(
        atSign,
        'chops',
        AtClientPreference()
          ..hiveStoragePath = dir.path
          ..commitLogPath = '${dir.path}/commit',
        remoteSecondary: MockRemoteSecondary(),
        atChops: AtChopsImpl(keys));
    client.syncService = MockSyncService();
    return client;
  }

  AtChopsKeys allKeys() => AtChopsKeys.create(encryptionKeyPair, pkamKeyPair)
    ..selfEncryptionKey = selfEncryptionKey;

  test('every key getter answers from the AtChops when nothing else holds it',
      () async {
    final local = (await clientHolding(allKeys())).getLocalSecondary()!;

    expect(await local.getEncryptionPrivateKey(),
        encryptionKeyPair.atPrivateKey.privateKey);
    expect(await local.getEncryptionPublicKey(atSign),
        encryptionKeyPair.atPublicKey.publicKey);
    expect(await local.getEncryptionSelfKey(), selfEncryptionKey.key);
    expect(
        await local.getPkamPrivateKey(), pkamKeyPair.atPrivateKey.privateKey);
    expect(await local.getPkamPublicKey(), pkamKeyPair.atPublicKey.publicKey);
  });

  test('a self value is written and read back with only the AtChops keys',
      () async {
    final client = await clientHolding(allKeys());
    final key =
        AtKey.self('phone', namespace: 'chops', sharedBy: atSign).build();

    expect(await client.put(key, 'from the AtChops'), isTrue,
        reason: 'a client built this way holds its keys nowhere else until '
            'its caller writes them to the keystore');
    expect((await client.get(key)).value, 'from the AtChops');
  });

  test('the keystore wins over the AtChops', () async {
    final local = (await clientHolding(allKeys())).getLocalSecondary()!;
    final stored = AESKey.generate(32).key;
    await local.putValue(AtConstants.atEncryptionSelfKey, stored);

    expect(await local.getEncryptionSelfKey(), stored);
  });

  test(
      'an AtChops built from a keyfile with no encryption keypair supplies none',
      () async {
    const enrollmentId = 'no-encryption-pair';
    final keyfile = await (await typedKeyfile(atSign,
            enrollmentId: enrollmentId, withAtSignKeys: false))
        .read(atSign);
    final chops = keyfile.authenticationFor(enrollmentId).chops as AtChopsImpl;
    final local = (await clientHolding(chops.atChopsKeys)).getLocalSecondary()!;

    expect(await local.getPkamPublicKey(),
        chops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey,
        reason: 'the control: this AtChops is consulted');
    await expectLater(
        local.getEncryptionPrivateKey, throwsA(isA<KeyNotFoundException>()),
        reason: 'its encryption keypair is empty strings standing in for one '
            'it was built without, and an empty key handed onward is sealed '
            'or signed with as if it were real');
    await expectLater(() => local.getEncryptionPublicKey(atSign),
        throwsA(isA<KeyNotFoundException>()));
  });

  test('a key held nowhere is still the keystore\'s exception', () async {
    final local = (await clientHolding(AtChopsKeys.create(null, pkamKeyPair)))
        .getLocalSecondary()!;

    await expectLater(
        local.getEncryptionPrivateKey, throwsA(isA<KeyNotFoundException>()),
        reason: 'callers tell an absent key by this exception');
  });
}
