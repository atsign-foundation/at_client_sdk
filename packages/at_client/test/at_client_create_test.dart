import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/durable_address_finder.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
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
    final client = await buildAtClient(
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

  test(
      'every connection of the client resolves its atServer through one '
      'durable finder', () async {
    final client = await buildAtClient(
        atSign: '@factoryaddr', namespace: 'wavi', preference: pref());

    final own = (client as AtClientImpl).secondaryAddressFinder;
    expect(own, isA<DurableSecondaryAddressFinder>());
    expect((own as DurableSecondaryAddressFinder).atSign, '@factoryaddr');
    expect(
        (client.getRemoteSecondary()!.atLookUp as AtLookupImpl)
            .secondaryAddressFinder,
        same(own),
        reason: 'the client\'s own connection');
    expect(
        (client.notificationService as NotificationServiceImpl)
            .secondaryAddressFinder,
        same(own),
        reason: 'the monitor\'s connection');
    expect(
        (SyncServiceImpl.remoteSecondaryFor(client).atLookUp as AtLookupImpl)
            .secondaryAddressFinder,
        same(own),
        reason: 'sync\'s connection; a start that cannot reach the '
            'atDirectory has to find the atServer on all three');

    await client.stop();
  });

  test('the client is filed in the instance map, though not as the current one',
      () async {
    final client = await buildAtClient(
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
    final client = await buildAtClient(
        atSign: '@factorywired', namespace: 'wavi', preference: pref());

    expect(() => client.syncService, returnsNormally);
    expect(() => client.notificationService, returnsNormally);
    expect(client.enrollmentService, isNotNull);

    await client.stop();
  });

  test('a builder replaces the service it names', () async {
    final noOp = NoOpSyncService();
    final client = await buildAtClient(
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
    final first = await buildAtClient(
        atSign: '@factorytwice', namespace: 'wavi', preference: pref());

    await expectLater(
        () => buildAtClient(
            atSign: '@factorytwice', namespace: 'wavi', preference: pref()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('already live'))),
        reason: 'handing back a client this caller does not own would discard '
            'every argument it passed');

    await first.stop();
    final second = await buildAtClient(
        atSign: '@factorytwice', namespace: 'wavi', preference: pref());
    expect(second, isNot(same(first)),
        reason: 'stop() frees the atSign, so the refusal is about a LIVE '
            'client rather than the atSign having been used once');

    await second.stop();
  });

  test('another enrollment of the same atSign builds beside the first',
      () async {
    const atSign = '@factorytwo';
    // Refused at once, so nothing here waits on a network.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final refusedPort = socket.port;
    await socket.close();
    // One store per principal, as two enrollments always have: a store is
    // held by the principal that opened it.
    AtClientPreference offline(String principal) => pref()
      ..hiveStoragePath = '${dir.path}/$principal'
      ..rootDomain = InternetAddress.loopbackIPv4.address
      ..rootPort = refusedPort;
    // A legacy keyfile enrolled as [enrollmentId]; the key material is any
    // demo atSign's, since nothing here reaches an atServer.
    AtKeys keysAs(String enrollmentId) => AtKeys()
      // ignore: deprecated_member_use
      ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap['@alice🛠']!)
      // ignore: deprecated_member_use
      ..apkamPrivateKey =
          AtBytes.fromString(demo.pkamPrivateKeyMap['@alice🛠']!)
      // ignore: deprecated_member_use
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(demo.encryptionPublicKeyMap['@alice🛠']!)
      // ignore: deprecated_member_use
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(demo.encryptionPrivateKeyMap['@alice🛠']!)
      // ignore: deprecated_member_use
      ..defaultSelfEncryptionKey =
          AtBytes.fromString(demo.aesKeyMap['@alice🛠']!)
      // ignore: deprecated_member_use
      ..enrollmentId = enrollmentId;
    Future<AtClient> build(String enrollmentId) => buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: offline(enrollmentId),
        atKeysIo: InMemoryAtKeysIo.holding(atSign, keysAs(enrollmentId)));

    final first = await build('e1');
    final second = await build('e2');

    expect(second, isNot(same(first)));
    expect((first.enrollmentId, second.enrollmentId), ('e1', 'e2'),
        reason: 'two enrollments of one atSign are two principals, each '
            'with its own client');
    await expectLater(
        () => build('e1'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('as enrollment e1'))),
        reason: 'the refusal is about the same principal being live, and '
            'names it');

    final own = await buildAtClient(
        atSign: atSign, namespace: 'wavi', preference: offline('own'));
    expect(own.enrollmentId, isNull,
        reason: 'the atSign\'s own credential is a third principal: with '
            'enrolled clients live, a caller naming no enrollment is not '
            'handed one of them');

    await own.stop();
    await second.stop();
    await first.stop();
  });

  test('buildRemoteSecondary carries the client identity a preference cannot',
      () async {
    final client = await buildAtClient(
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
        () => buildAtClient(
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

  test('a client that fails to build is not left behind', () async {
    final first = HiveAtClientStorage(
        atSign: '@factoryhalfbuilt',
        storagePath: dir.path,
        closedByClient: true);

    await expectLater(
        () => buildAtClient(
            atSign: '@factoryhalfbuilt',
            namespace: 'wavi',
            preference: pref(),
            storage: first,
            syncServiceBuilder: (_) => throw StateError('builder exploded')),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('builder exploded'))));

    // The client is filed before its services are wired, so a throw here can
    // strand an entry nothing holds a reference to. Asserted directly, before
    // the second create below - which would otherwise trip over the stranded
    // entry and fail on a bare StateError instead of on this reason.
    expect(AtClientImpl.atClientInstanceMap.containsKey('@factoryhalfbuilt'),
        isFalse,
        reason: 'a client whose build threw is unfiled, rather than sitting in '
            'the instance map where the next setCurrentAtSign adopts and later '
            'stops it - while the caller that asked for it holds no reference '
            'and cannot stop it itself');

    final second = HiveAtClientStorage(
        atSign: '@factoryhalfbuilt',
        storagePath: dir.path,
        closedByClient: true);
    final client = await buildAtClient(
        atSign: '@factoryhalfbuilt',
        namespace: 'wavi',
        preference: pref(),
        storage: second);

    expect(second.isHeldBy(client), isTrue,
        reason: 'the same stop() that unfiled it also released its claim on '
            'the location, so a later client can open a store there - '
            'otherwise one failed build makes that directory unusable for the '
            'life of the process');

    await client.stop();
    expect(first.isHeldBy(client), isFalse);
  });
}
