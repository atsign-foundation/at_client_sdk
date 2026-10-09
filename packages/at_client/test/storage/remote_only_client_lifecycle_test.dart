import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

AtKeys _demoKeys() => AtKeys()
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

void main() {
  late MockRemoteSecondary remote;

  setUpAll(() {
    registerFallbackValue(LLookupVerbBuilder());
  });

  setUp(() {
    AtClientManager.getInstance().reset();
    remote = MockRemoteSecondary();
    final lookUp = remote.atLookUp;
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => remote.executeVerb(any()))
        .thenThrow(KeyNotFoundException('not on the server'));
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
  });

  // NOTE: isLocalStoreRequired left at its default, true.
  AtClientPreference defaultPref() => AtClientPreference()
    ..namespace = 'wavi'
    ..monitorAutoStart = false;

  Future<(AtClientImpl, RemoteOnlyAtClientStorage)> remoteOnly(
      String atSign) async {
    final storage = RemoteOnlyAtClientStorage(
        atSign: atSign, remoteSecondary: remote, closedByClient: true);
    final client = await AtClientImpl.create(atSign, 'wavi', defaultPref(),
        remoteSecondary: remote,
        storage: storage,
        atKeysIo: InMemoryAtKeysIo.holding(atSign, _demoKeys()));
    return (client as AtClientImpl, storage);
  }

  test('a remote-only client runs no timers over a replica it does not hold',
      () async {
    final (client, _) = await remoteOnly('@lc1');

    expect(client.expiryTimerArmedForTest, isFalse);
    expect(client.availableTimerArmedForTest, isFalse);
  });

  test('a rederive moves the storage onto the new RemoteSecondary', () async {
    final (client, storage) = await remoteOnly('@lc2');

    await client.rederiveFromEnrollmentForTest(previousEnrollmentId: null);

    expect(identical(client.getRemoteSecondary(), remote), isFalse);
    expect(storage.remoteSecondary, same(client.getRemoteSecondary()));
  });

  test('a rederive leaves a storage on some other RemoteSecondary alone',
      () async {
    const atSign = '@lc3';
    final own = MockRemoteSecondary();
    final storage = RemoteOnlyAtClientStorage(
        atSign: atSign, remoteSecondary: own, closedByClient: true);
    final client = await AtClientImpl.create(atSign, 'wavi', defaultPref(),
        remoteSecondary: remote,
        storage: storage,
        atKeysIo: InMemoryAtKeysIo.holding(atSign, _demoKeys())) as AtClientImpl;

    await client.rederiveFromEnrollmentForTest(previousEnrollmentId: null);

    expect(storage.remoteSecondary, same(own));
  });
}
