import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'test_utils/no_op_services.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('at_client_create_');
    AtClientManager.getInstance().reset();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  AtClientPreference pref() => AtClientPreference()..hiveStoragePath = dir.path;

  test('the client holds the storage it was given', () async {
    final storage =
        HiveAtClientStorage(atSign: '@factoryheld', storagePath: dir.path);
    final client = await AtClient.create(
        atSign: '@factoryheld',
        namespace: 'wavi',
        preference: pref(),
        storage: storage);

    expect(storage.isHeldBy(client), isTrue,
        reason: 'the bundle the caller supplied is the one the client opened, '
            'not a Hive store built from preference.hiveStoragePath');

    await client.stop();
    await storage.close();
  });

  test('nothing is registered with AtClientManager', () async {
    final client = await AtClient.create(
        atSign: '@factorysolo', namespace: 'wavi', preference: pref());

    expect(client.getCurrentAtSign(), '@factorysolo');
    expect(() => AtClientManager.getInstance().atClient, throwsStateError,
        reason: 'the factory builds a client the caller owns; only '
            'setCurrentAtSign fills in the shared current-atSign client');

    await client.stop();
  });

  test('the services are wired', () async {
    final client = await AtClient.create(
        atSign: '@factorywired', namespace: 'wavi', preference: pref());

    expect(() => client.syncService, returnsNormally);
    expect(() => client.notificationService, returnsNormally);
    expect(client.enrollmentService, isNotNull);

    await client.stop();
  });

  test('a builder replaces the service it names', () async {
    final noOp = NoOpSyncService();
    final client = await AtClient.create(
        atSign: '@factorybuilder',
        namespace: 'wavi',
        preference: pref(),
        syncServiceBuilder: (_) => noOp);

    expect(client.syncService, same(noOp),
        reason: 'the caller\'s builder is what supplied the service, rather '
            'than SyncServiceImpl.create');

    await client.stop();
  });

  test('an atSign whose client is live is refused; stop() releases it',
      () async {
    final first = await AtClient.create(
        atSign: '@factorytwice', namespace: 'wavi', preference: pref());

    await expectLater(
        () => AtClient.create(
            atSign: '@factorytwice', namespace: 'wavi', preference: pref()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('already live'))),
        reason: 'handing back a client this caller does not own would discard '
            'every argument it passed');

    await first.stop();
    final second = await AtClient.create(
        atSign: '@factorytwice', namespace: 'wavi', preference: pref());
    expect(second, isNot(same(first)),
        reason: 'stop() frees the atSign, so the refusal is about a LIVE '
            'client rather than the atSign having been used once');

    await second.stop();
  });

  test('storage the preference would never open is refused', () async {
    final storage =
        HiveAtClientStorage(atSign: '@factorynolocal', storagePath: dir.path);

    await expectLater(
        () => AtClient.create(
            atSign: '@factorynolocal',
            namespace: 'wavi',
            preference: pref()..isLocalStoreRequired = false,
            storage: storage),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('isLocalStoreRequired'))),
        reason: 'a caller that named its own backend must not be told it took '
            'effect when the client opens no local store at all');

    await storage.close();
  });
}
