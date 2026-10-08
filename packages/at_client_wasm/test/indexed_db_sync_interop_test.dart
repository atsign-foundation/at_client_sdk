// ignore_for_file: implementation_imports
import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client_wasm/src/storage/indexed_db_at_client_storage.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'support/mocks.dart';
import 'support/stateful_remote.dart';

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

// Removed custom InMemoryAtKeysIo

void main() {
  setUpAll(() => registerFallbackValue(LLookupVerbBuilder()));

  late StatefulFakeServer server;
  int counter = 0;
  String nextEnrollmentId() =>
      'e${counter++}_${DateTime.now().millisecondsSinceEpoch}';

  final dbToDelete = <(String, String)>[];

  setUp(() async {
    AtClientManager.getInstance().reset();
    server = StatefulFakeServer(_atSign);
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();

    for (final db in dbToDelete) {
      await IndexedDbAtClientStorage.deleteDatabase(
          atSign: db.$1, enrollmentId: db.$2);
    }
    dbToDelete.clear();
  });

  Future<AtClient> idbClient() {
    final e = nextEnrollmentId();
    dbToDelete.add((_atSign, e));
    return buildAtClient(
        atSign: _atSign,
        namespace: 'wavi',
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        storage: IndexedDbAtClientStorage(
            atSign: _atSign, enrollmentId: e, closedByClient: true),
        atKeysIo: InMemoryAtKeysIo.holding(_atSign, _demoKeys()),
        lookUps: _offline,
        syncServiceBuilder: (c) =>
            SyncServiceImpl.create(c, remoteSecondary: server.remote));
  }

  Future<AtClient> remoteOnlyClient() => buildAtClient(
      atSign: _atSign,
      namespace: 'wavi',
      preference: AtClientPreference()
        // ignore: deprecated_member_use
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

  test('a remote-only client reads what an IDB client wrote and synced',
      () async {
    final writer = await idbClient();
    await writer.put(greeting(), 'hello from idb');
    await writer.syncService.waitUntilCaughtUp(timeout: _timeout);
    await writer.stop();

    final stored = server.storedValue('greeting.wavi$_atSign');
    expect(stored, isNotNull);
    expect(stored, isNot('hello from idb'));

    final reader = await remoteOnlyClient();
    expect((await reader.get(greeting())).value, 'hello from idb');
    await reader.stop();
  });

  test('an IDB client syncs and reads what a remote-only client wrote',
      () async {
    final writer = await remoteOnlyClient();
    await writer.put(greeting(), 'hello from remote');
    await writer.stop();

    final stored = server.storedValue('greeting.wavi$_atSign');
    expect(stored, isNotNull);
    expect(stored, isNot('hello from remote'));

    final reader = await idbClient();
    await reader.syncService.waitUntilCaughtUp(timeout: _timeout);
    expect((await reader.get(greeting())).value, 'hello from remote');
    await reader.stop();
  });
}
