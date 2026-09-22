import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// A throwaway [AtClient] identity used only to seed an [InMemoryAtClientStorage]
/// before handing it to [buildAtClient] for the client under test.
class _SeedingClient extends Mock implements AtClient {
  _SeedingClient(this._atSign);
  final String _atSign;
  @override
  String? getCurrentAtSign() => _atSign;
  @override
  String? get enrollmentId => null;
}

/// A legacy keyfile for `atSign`, keyed off any demo atSign's real material
/// since nothing here reaches an atServer.
AtKeys _demoKeys(String atSign) => AtKeys()
  // ignore: deprecated_member_use
  ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..defaultEncryptionPublicKey =
      AtBytes.fromString(demo.encryptionPublicKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..defaultEncryptionPrivateKey =
      AtBytes.fromString(demo.encryptionPrivateKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap['@alice🛠']!);

/// Never touches the network: every construction here is about storage/chops
/// plumbing, not connectivity.
AtLookupMuxable _recording({
  required String atSign,
  required AtRootDomain rootDomain,
  required AtAuthenticator? authenticator,
  SecondaryAddressFinder? secondaryAddressFinder,
  Map<String, dynamic> clientConfig = const {},
}) {
  final lookUp = MockAtLookupImpl();
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((_) async => 'data:null');
  return lookUp;
}

void main() {
  setUp(() => AtClientManager.getInstance().reset());

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
  });

  AtClientPreference remotePref() => AtClientPreference()
    ..isLocalStoreRequired = false
    ..namespace = 'wavi'
    ..monitorAutoStart = false;

  test(
      'a non-Hive storage with isLocalStoreRequired false constructs, and '
      'reads/writes flow through it', () async {
    const atSign = '@modee1';
    final storage = InMemoryAtClientStorage(atSign: atSign);

    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: remotePref(),
        storage: storage,
        lookUps: _recording) as AtClientImpl;

    expect(client.localSecondary, isNotNull,
        reason: 'B1/B2 make this Mode E shape constructible at all');
    await storage.keyStore.put('k$atSign', AtData()..data = 'v');
    expect((await storage.keyStore.get('k$atSign'))?.data, 'v',
        reason: 'the storage handed to buildAtClient is the one attached, '
            'not a Hive fallback');

    await client.stop();
    await storage.close();
  });

  test('chops resolves via the injected AtKeysIo, never the empty keystore',
      () async {
    const atSign = '@modee2';
    final storage = InMemoryAtClientStorage(atSign: atSign);

    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: remotePref(),
        storage: storage,
        atKeysIo: InMemoryAtKeysIo.holding(atSign, _demoKeys(atSign)),
        lookUps: _recording) as AtClientImpl;

    expect(
        client.atChops?.atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey,
        demo.pkamPublicKeyMap['@alice🛠'],
        reason: 'the keystore behind `storage` was never written to, so this '
            'can only have come from AtKeysIo');

    await client.stop();
    await storage.close();
  });

  test(
      'chops resolves through a pre-seeded non-Hive keystore when no AtKeysIo '
      'is injected', () async {
    const atSign = '@modee3';
    final storage = InMemoryAtClientStorage(atSign: atSign);
    final seeder = _SeedingClient(atSign);
    await storage.attach(seeder);
    await storage.keyStore.put(AtConstants.atPkamPublicKey,
        AtData()..data = demo.pkamPublicKeyMap['@alice🛠']);
    await storage.keyStore.put(AtConstants.atPkamPrivateKey,
        AtData()..data = demo.pkamPrivateKeyMap['@alice🛠']);
    await storage.keyStore.put('${AtConstants.atEncryptionPublicKey}$atSign',
        AtData()..data = demo.encryptionPublicKeyMap['@alice🛠']);
    await storage.keyStore.put(AtConstants.atEncryptionPrivateKey,
        AtData()..data = demo.encryptionPrivateKeyMap['@alice🛠']);
    await storage.detach(seeder);

    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: remotePref(),
        storage: storage,
        lookUps: _recording) as AtClientImpl;

    expect(
        client.atChops?.atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey,
        demo.pkamPublicKeyMap['@alice🛠'],
        reason: 'proves the `?.`-fixed _createAtChops reads through a '
            'non-Hive keystore rather than degrading to the empty-keypair '
            'fallback');

    await client.stop();
    await storage.close();
  });

  test(
      'expiry/availability timers do not arm when storage is injected and '
      'isLocalStoreRequired is false', () async {
    const atSign = '@modee4';
    final storage = InMemoryAtClientStorage(atSign: atSign);
    // Seeds a record with a future expiresAt/availableAt.
    final seeder = _SeedingClient(atSign);
    await storage.attach(seeder);
    final future = DateTime.timestamp().add(const Duration(hours: 1));
    await storage.keyStore.put(
        'armworthy$atSign',
        AtData()
          ..data = 'v'
          ..metaData = (AtMetaData()
            ..expiresAt = future
            ..availableAt = future));
    await storage.detach(seeder);

    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: remotePref(),
        storage: storage,
        lookUps: _recording) as AtClientImpl;

    expect(client.localSecondary, isNotNull,
        reason: 'the timer gate and the storage/localSecondary gate are '
            'independent - localSecondary is set here even though the '
            'timers below are not armed');
    expect(client.expiryTimerArmedForTest, isFalse,
        reason: 'the timer block stayed gated on isLocalStoreRequired alone, '
            'not OR\'d with the injected-storage check');
    expect(client.availableTimerArmedForTest, isFalse);

    // Positive control.
    await client.armExpiryTimerForTest();
    await client.armAvailableTimerForTest();
    expect(client.expiryTimerArmedForTest, isTrue,
        reason: 'the seeded record is arm-worthy, so the false above is the '
            'gate at work and not an empty store');
    expect(client.availableTimerArmedForTest, isTrue);

    await client.stop();
    await storage.close();
  });
}
