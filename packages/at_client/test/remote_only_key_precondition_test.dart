// PB-3 stage3 (R3): a remote-only client never infers key material from a
// store that never held it. See plans/wasm/spike/pb3-stage3-r3-plan.md.

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

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
    // A server miss, as the write-through keystore would surface it.
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

  AtClientPreference remotePref() => AtClientPreference()
    ..isLocalStoreRequired = false
    ..namespace = 'wavi'
    ..monitorAutoStart = false;

  test('holdsKeyMaterial: false for remote-only, true for a local backend', () {
    expect(
        RemoteOnlyAtClientStorage(atSign: '@r3a', remoteSecondary: remote)
            .holdsKeyMaterial,
        isFalse);
    expect(InMemoryAtClientStorage(atSign: '@r3a').holdsKeyMaterial, isTrue);
  });

  test(
      'no atChops and no atKeysIo: construction throws StateError and never '
      'asks the server for key material', () async {
    const atSign = '@r3b';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remote);

    await expectLater(
        AtClientImpl.create(atSign, 'wavi', remotePref(),
            remoteSecondary: remote, storage: storage),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('atKeysIo'))));
    verifyNever(() => remote.executeVerb(any()));
    await storage.close();
  });

  test('atKeysIo: constructs, chops come from AtKeysIo', () async {
    const atSign = '@r3c';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remote);

    final client = await AtClientImpl.create(atSign, 'wavi', remotePref(),
        remoteSecondary: remote,
        storage: storage,
        atKeysIo: InMemoryAtKeysIo.holding(atSign, _demoKeys()));

    expect(client.atChops?.atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey,
        demo.pkamPublicKeyMap['@alice🛠']);
    verifyNever(() => remote.executeVerb(any()));
    await client.stop();
    await storage.close();
  });

  test('injected atChops: constructs and keeps the injected instance',
      () async {
    const atSign = '@r3d';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remote);
    // ignore: deprecated_member_use
    final chops = AtChopsImpl(AtChopsKeys.create(null, null));

    final client = await AtClientImpl.create(atSign, 'wavi', remotePref(),
        remoteSecondary: remote,
        storage: storage,
        // ignore: deprecated_member_use
        atChops: chops);

    expect(identical(client.atChops, chops), isTrue);
    verifyNever(() => remote.executeVerb(any()));
    await client.stop();
    await storage.close();
  });
}
