import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
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

  test('the client is filed in the instance map, though not as the current one',
      () async {
    final client = await AtClient.create(
        atSign: '@factorysolo', namespace: 'wavi', preference: pref());

    expect(client.getCurrentAtSign(), '@factorysolo');
    expect(AtClientImpl.atClientInstanceMap['@factorysolo'], same(client),
        reason: 'AtClientImpl.create files every client it builds, this one '
            'included - so a later setCurrentAtSign for this atSign adopts '
            'THIS client rather than building its own. Asserting only that the '
            'manager has no current client passes before create() is ever '
            'called, which is what made the previous version of this test '
            'vacuous');
    expect(() => AtClientManager.getInstance().atClient, throwsStateError,
        reason: 'the manager\'s current client is still unset: create() does '
            'not make this the process-wide current atSign');

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

  test('buildRemoteSecondary carries the client identity a preference cannot',
      () async {
    final client = await AtClient.create(
        atSign: '@buildsecondary',
        namespace: 'wavi',
        preference: pref()..privateKey = 'dummy_private_key',
        enrollmentId: 'enrollment-under-test') as AtClientImpl;

    final built = client.buildRemoteSecondary();

    // enrollmentId, not the credential: RemoteSecondary recovers privateKey
    // from the preference on its own (`privateKey ??= preference.privateKey`),
    // so asserting on the authenticator passes whether or not the factory
    // threaded anything. The enrollment id is held by the client alone.
    expect(built.atLookUp.enrollmentId, 'enrollment-under-test',
        reason: 'every RemoteSecondary this client opens is configured FROM '
            'the client, so a second connection acts as the same enrollment '
            'rather than being assembled independently');
    expect((built.atLookUp as AtLookupMuxable).authenticator, isNotNull,
        reason: 'and it authenticates through the seam, not the ladder');

    await client.stop();
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
