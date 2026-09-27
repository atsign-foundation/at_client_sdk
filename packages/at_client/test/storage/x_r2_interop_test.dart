// X-R2 (acceptance.md §9a.2): a Hive-backed client and a
// RemoteOnlyAtClientStorage-backed client read each other's writes through
// one atServer. The clients run one after the other — one live client per
// atSign — over a StatefulFakeServer that both reach.

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/stateful_remote.dart';

const _atSign = '@alice🛠';
const _timeout = Duration(seconds: 10);

AtLookupMuxable _offline({
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
  return lookUp;
}

AtKeys _demoKeys() => AtKeys()
  // ignore: deprecated_member_use
  ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[_atSign]!)
  // ignore: deprecated_member_use
  ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[_atSign]!)
  // ignore: deprecated_member_use
  ..defaultEncryptionPublicKey =
      AtBytes.fromString(demo.encryptionPublicKeyMap[_atSign]!)
  // ignore: deprecated_member_use
  ..defaultEncryptionPrivateKey =
      AtBytes.fromString(demo.encryptionPrivateKeyMap[_atSign]!)
  // ignore: deprecated_member_use
  ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap[_atSign]!);

void main() {
  setUpAll(() => registerFallbackValue(LLookupVerbBuilder()));

  late StatefulFakeServer server;
  late Directory hiveDir;

  setUp(() async {
    AtClientManager.getInstance().reset();
    server = StatefulFakeServer(_atSign);
    hiveDir = await Directory.systemTemp.createTemp('x_r2_');
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    await hiveDir.delete(recursive: true);
  });

  Future<AtClient> hiveClient() => buildAtClient(
      atSign: _atSign,
      namespace: 'wavi',
      preference: AtClientPreference()
        ..namespace = 'wavi'
        ..monitorAutoStart = false
        ..hiveStoragePath = hiveDir.path
        ..commitLogPath = '${hiveDir.path}/commit',
      atKeysIo: InMemoryAtKeysIo.holding(_atSign, _demoKeys()),
      lookUps: _offline,
      syncServiceBuilder: (c) =>
          SyncServiceImpl.create(c, remoteSecondary: server.remote));

  Future<AtClient> remoteOnlyClient() => buildAtClient(
      atSign: _atSign,
      namespace: 'wavi',
      preference: AtClientPreference()
        ..isLocalStoreRequired = false
        ..namespace = 'wavi'
        ..monitorAutoStart = false,
      storage: RemoteOnlyAtClientStorage(
          atSign: _atSign,
          remoteSecondary: server.remote,
          closedByClient: true),
      atKeysIo: InMemoryAtKeysIo.holding(_atSign, _demoKeys()),
      lookUps: _offline);

  AtKey greeting() =>
      AtKey.self('greeting', namespace: 'wavi', sharedBy: _atSign).build();

  test('a remote-only client reads what a Hive client wrote and synced',
      () async {
    final writer = await hiveClient();
    await writer.put(greeting(), 'hello from hive');
    await writer.syncService.waitUntilCaughtUp(timeout: _timeout);
    await writer.stop();

    final stored = server.storedValue('greeting.wavi$_atSign');
    expect(stored, isNotNull, reason: 'sync pushed the write to the atServer');
    expect(stored, isNot('hello from hive'),
        reason: 'a self key reaches the atServer encrypted');

    final reader = await remoteOnlyClient();
    expect((await reader.get(greeting())).value, 'hello from hive');
    await reader.stop();
  });

  test('a Hive client syncs and reads what a remote-only client wrote',
      () async {
    final writer = await remoteOnlyClient();
    await writer.put(greeting(), 'hello from remote');
    await writer.stop();

    final stored = server.storedValue('greeting.wavi$_atSign');
    expect(stored, isNotNull, reason: 'write-through lands on the atServer');
    expect(stored, isNot('hello from remote'),
        reason: 'a self key reaches the atServer encrypted');

    final reader = await hiveClient();
    await reader.syncService.waitUntilCaughtUp(timeout: _timeout);
    expect((await reader.get(greeting())).value, 'hello from remote');
    await reader.stop();
  });
}
