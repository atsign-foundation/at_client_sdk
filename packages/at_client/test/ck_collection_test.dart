import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart'
    show collectUnusedOnceCaughtUp;
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Local storage as a keystore holds it: canonical key strings, each with its
/// value and the metadata sync carried in.
class _Store extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  final Map<String, AtData> data = {};

  @override
  Future<Stream<String>> getKeys({String? regex}) async => Stream.fromIterable(
      data.keys.where((k) => regex == null || RegExp(regex).hasMatch(k)));

  @override
  Future<AtData?> get(String key) async => data[key];

  @override
  Future<AtMetaData?> getMeta(String key) async => data[key]?.metaData;
}

class _FakeListener extends Fake implements SyncProgressListener {}

/// Collecting the content keys an enrollment cut and nothing cites any more.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';
  const enrollmentId = 'enr-1';

  late XWingKeyPair aliceNskey;
  late XWingKeyPair bobNskey;

  setUpAll(() async {
    aliceNskey = await XWingKeyPair.generate();
    bobNskey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
    registerFallbackValue(_FakeListener());
  });

  /// A client of alice, enrolled as [enrollmentId], whose writes land in
  /// [store] the way the pipeline leaves them.
  ///
  /// [supersededCkGrace] defaults to none, so a test sees what a pass deletes
  /// once a key's grace is over; null builds the config as an app naming no
  /// grace does.
  ({
    CkManager manager,
    ContentKeyCache cache,
    CryptoContext context,
    _Store store,
    List<String> deleted,
    MockAtClient client,
    MockSyncService sync,
    Completer<void> Function() parkNextConveyance,
  }) enrolled(
      {String? enrolledAs = enrollmentId,
      CkRotationPolicy ckRotationPolicy = rotateCkAfterOneWeek,
      Duration? supersededCkGrace = Duration.zero}) {
    final ring = InMemoryNskeyKeyRing()
      ..seedPublicOnly(bob, namespace, publicKey: bobNskey.publicKeyBytes)
      ..seedKeypair(alice, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes);
    final config = supersededCkGrace == null
        ? CryptoConfig.nskey(keyRing: ring, ckRotationPolicy: ckRotationPolicy)
        : CryptoConfig.nskey(
            keyRing: ring,
            ckRotationPolicy: ckRotationPolicy,
            supersededCkGrace: supersededCkGrace);
    final client = MockAtClient();
    client.getPreferences().crypto = config;
    when(() => client.getCurrentAtSign()).thenReturn(alice);
    when(() => client.enrollmentId).thenReturn(enrolledAs);
    final store = _Store();
    when(() => client.getLocalSecondary())
        .thenReturn(LocalSecondary(client, keyStore: store));
    final sync = MockSyncService();
    when(() => client.syncService).thenReturn(sync);
    when(() => sync.isInSync()).thenAnswer((_) async => true);

    Completer<void>? parked;
    when(() => client.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      var value = inv.positionalArguments[1] as String;
      final options =
          inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
      if (options?.shouldEncrypt ?? true) {
        key.metadata.appMetadata =
            AppMetadata(providerId: options!.cryptoProviderId!);
        value = await CryptoRuntime(client).encryptForPut(key, value);
      }
      store.data[key.toString()] = AtData()
        ..data = value
        ..metaData = AtMetaData.fromCommonsMetadata(key.metadata, alice);
      final waiting = parked;
      if (waiting != null && key.toString().contains('.__ck.')) {
        parked = null;
        await waiting.future;
      }
      return true;
    });
    final deleted = <String>[];
    when(() => client.delete(any(),
            isDedicated: any(named: 'isDedicated'),
            deleteRequestOptions: any(named: 'deleteRequestOptions')))
        .thenAnswer((inv) async {
      final key = (inv.positionalArguments[0] as AtKey).toString();
      deleted.add(key);
      store.data.remove(key);
      return true;
    });

    final data = config.lookup(symmetricAesGcmCryptoProviderId)
        as SymmetricAesGcmProvider;
    return (
      manager: data.ckManager!,
      cache: data.cache,
      context: CryptoContext(atClient: client),
      store: store,
      deleted: deleted,
      client: client,
      sync: sync,
      parkNextConveyance: () => parked = Completer<void>(),
    );
  }

  AtKey shared() => AtKey()
    ..key = 'pact'
    ..namespace = namespace
    ..sharedWith = bob
    ..sharedBy = alice
    ..metadata = Metadata();

  /// A value in local storage citing [ckKid], as a value written under it is.
  void cite(_Store store, String ckKid, {String name = 'pact'}) =>
      store.data['$bob:$name.$namespace$alice'] = AtData()
        ..data = 'ciphertext'
        ..metaData = (AtMetaData()
          ..appMetadata = AppMetadata(
              providerId: symmetricAesGcmCryptoProviderId,
              additional: {'ckKid': ckKid, 'ckNs': namespace}));

  /// A conveyance nothing else in the fixture wrote, carrying [ckKid].
  void conveyance(_Store store, String ckKid,
          {String? cutBy, DateTime? createdAt}) =>
      store.data['$bob:$ckKid.__ck.$namespace$alice'] = AtData()
        ..data = 'sealed'
        ..metaData = (AtMetaData()
          ..createdAt = createdAt
          ..appMetadata =
              AppMetadata(providerId: nskeyCryptoProviderId, additional: {
            'recipientKind': 'nskey',
            'ckKid': ckKid,
            'ns': namespace,
            if (cutBy != null) 'cutBy': cutBy,
          }));

  List<String> conveyancesOf(String ckKid) => [
        '$bob:$ckKid.__ck.$namespace$alice',
        '$ckKid.__ck.$namespace$alice',
      ];

  /// Backdates the conveyances of [ckKid] to say it was cut [ago].
  void cutAgo(_Store store, String ckKid, Duration ago) {
    for (final key in conveyancesOf(ckKid)) {
      store.data[key]!.metaData!.createdAt = DateTime.now().subtract(ago);
    }
  }

  group('the grace a superseded key is kept for', () {
    test('defaults to 8 days', () {
      expect(
          CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()).supersededCkGrace,
          const Duration(days: 8),
          reason: 'the longest an atServer keeps a notification');
    });

    test('by default, a superseded key nothing cites is kept', () async {
      final a = enrolled(supersededCkGrace: null);
      await a.manager.ensureCurrent(a.context, shared());
      final superseded = a.cache.current(bob, namespace)!.ckKid;
      await a.manager.rotateContentKey(a.context, shared());
      await a.manager.idle;

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.store.data.keys, containsAll(conveyancesOf(superseded)),
          reason: 'a recipient may still hold a notification sent under it');

      final control = enrolled();
      await control.manager.ensureCurrent(control.context, shared());
      final gone = control.cache.current(bob, namespace)!.ckKid;
      await control.manager.rotateContentKey(control.context, shared());
      await control.manager.idle;
      expect(control.deleted.toSet(), conveyancesOf(gone).toSet(),
          reason: 'the control: with no grace the same key goes');
    });

    test('counts from the cut of its successor, not its own', () async {
      final a = enrolled(supersededCkGrace: const Duration(days: 8));
      await a.manager.ensureCurrent(a.context, shared());
      final superseded = a.cache.current(bob, namespace)!.ckKid;
      final successor =
          (await a.manager.rotateContentKey(a.context, shared())).ckKid;
      await a.manager.idle;
      cutAgo(a.store, superseded, const Duration(days: 30));
      cutAgo(a.store, successor, const Duration(days: 1));

      expect(await a.manager.collectUnused(a.context), 0,
          reason: 'cut a month ago, but superseded only yesterday');

      cutAgo(a.store, successor, const Duration(days: 9));
      expect(await a.manager.collectUnused(a.context), 1);
      expect(a.deleted.toSet(), conveyancesOf(superseded).toSet(),
          reason: 'its successor is current, so it alone goes');
    });

    test('a key with no successor counts from its own cut', () async {
      final a = enrolled(supersededCkGrace: const Duration(days: 8));
      conveyance(a.store, 'orphan0000000000',
          cutBy: enrollmentId,
          createdAt: DateTime.now().subtract(const Duration(days: 1)));
      expect(await a.manager.collectUnused(a.context), 0);

      conveyance(a.store, 'orphan0000000000',
          cutBy: enrollmentId,
          createdAt: DateTime.now().subtract(const Duration(days: 9)));
      expect(await a.manager.collectUnused(a.context), 1);
      expect(a.deleted, ['$bob:orphan0000000000.__ck.$namespace$alice']);
    });
  });

  group('collecting unused content keys', () {
    test(
        'a rotation collects the key it superseded, which nothing cites — both '
        'conveyances', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      final superseded = a.cache.current(bob, namespace)!.ckKid;
      await a.manager.rotateContentKey(a.context, shared());
      final current = a.cache.current(bob, namespace)!.ckKid;
      await a.manager.idle;

      expect(a.deleted.toSet(), conveyancesOf(superseded).toSet());
      expect(a.store.data.keys, containsAll(conveyancesOf(current)));
      expect(a.cache.get(bob, namespace, superseded), isNull,
          reason: 'and this client stops using the copy it already holds');
    });

    test('a superseded key a record still cites is kept', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      cite(a.store, a.cache.current(bob, namespace)!.ckKid);
      await a.manager.rotateContentKey(a.context, shared());
      await a.manager.idle;

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.deleted, isEmpty,
          reason: 'deleting it would leave that record unreadable');
    });

    test('a key replaced on the policy\'s say-so is collected too', () async {
      final a = enrolled(ckRotationPolicy: (_) async => true);
      await a.manager.ensureCurrent(a.context, shared());
      final superseded = a.cache.current(bob, namespace)!.ckKid;
      await a.manager.ensureCurrent(a.context, shared());
      await a.manager.idle;

      expect(a.cache.current(bob, namespace)!.ckKid, isNot(superseded));
      expect(a.deleted.toSet(), conveyancesOf(superseded).toSet());
    });

    test('the current key is kept although nothing cites it yet', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.deleted, isEmpty,
          reason: 'its conveyance lands just before the first value citing it');
    });

    test('after a restart, the key the pointer names is kept', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      // Nothing in memory, as after a restart: only the pointer names it.
      a.cache.evict(bob, namespace, a.cache.current(bob, namespace)!.ckKid);

      expect(await a.manager.collectUnused(a.context), 0);
    });

    test('a key current only in memory is kept', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      // The pointer write is swallowed when it fails, leaving the key current
      // here and named nowhere durable.
      a.store.data.removeWhere((key, _) => key.startsWith('__ckcur.'));

      expect(await a.manager.collectUnused(a.context), 0);
    });

    test('a key cut and never made current is collected', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      conveyance(a.store, 'orphan0000000000', cutBy: enrollmentId);

      expect(await a.manager.collectUnused(a.context), 1);
      expect(a.deleted, ['$bob:orphan0000000000.__ck.$namespace$alice'],
          reason: 'a stop between a conveyance and its pointer leaves a key '
              'nothing will ever cite');
    });

    test('a key another enrollment cut is left alone', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      conveyance(a.store, 'sibling000000000', cutBy: 'enr-2');

      expect(await a.manager.collectUnused(a.context), 0,
          reason: 'this enrollment cannot see that one\'s pointer, so cannot '
              'tell a key about to be cited from an unused one');
    });

    test('a conveyance naming no cutter is left alone', () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      conveyance(a.store, 'nocutter00000000');

      expect(await a.manager.collectUnused(a.context), 0);
    });

    test('a collection waits for a cut in progress', () async {
      final a = enrolled();
      final release = a.parkNextConveyance();
      final cutting = a.manager.ensureCurrent(a.context, shared());
      // The recipient's conveyance is in the store, the key not yet current.
      await Future<void>.delayed(Duration.zero);
      final collecting = a.manager.collectUnused(a.context);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await cutting;

      expect(await collecting, 0,
          reason: 'run between the conveyance and its promotion, it would '
              'delete a key the next value cites');
      expect(a.deleted, isEmpty);
    });
  });

  group('collecting nothing where local storage may be partial', () {
    /// A superseded, uncited key, which the rotation's collection and any
    /// later one would otherwise delete.
    Future<({CkManager manager, CryptoContext context, List<String> deleted})>
        withGarbage(
            void Function(MockAtClient client, MockSyncService sync) narrow,
            {String? enrolledAs = enrollmentId}) async {
      final a = enrolled(enrolledAs: enrolledAs);
      await a.manager.ensureCurrent(a.context, shared());
      narrow(a.client, a.sync);
      await a.manager.rotateContentKey(a.context, shared());
      await a.manager.idle;
      return (manager: a.manager, context: a.context, deleted: a.deleted);
    }

    test('the control: with nothing narrowed, the key goes', () async {
      final a = await withGarbage((_, __) {});

      expect(a.deleted, hasLength(2));
    });

    test('while sync has not caught up', () async {
      final a = await withGarbage((_, sync) =>
          when(() => sync.isInSync()).thenAnswer((_) async => false));

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.deleted, isEmpty);
    });

    test('when a syncRegex narrows what local storage holds', () async {
      final a = await withGarbage(
          (client, _) => client.getPreferences().syncRegex = 'my_apps');

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.deleted, isEmpty);
    });

    test('on a client that keeps no local store', () async {
      final a = await withGarbage(
          (client, _) => client.getPreferences().isLocalStoreRequired = false);

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.deleted, isEmpty);
    });

    test('on a client with no enrollment id', () async {
      final a = await withGarbage((client, _) {
        when(() => client.enrollmentId).thenReturn(null);
      });

      expect(await a.manager.collectUnused(a.context), 0);
      expect(a.deleted, isEmpty);
    });
  });

  group('at each start', () {
    test('a collection runs once sync first reports this client caught up',
        () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      conveyance(a.store, 'orphan0000000000', cutBy: enrollmentId);
      final listeners = <SyncProgressListener>[];
      when(() => a.sync.addProgressListener(any()))
          .thenAnswer((inv) => listeners.add(inv.positionalArguments[0]));

      final waiting =
          collectUnusedOnceCaughtUp(a.sync, () => a.manager, a.context);
      await Future<void>.delayed(Duration.zero);
      expect(a.deleted, isEmpty, reason: 'nothing before sync has caught up');

      for (final listener in List.of(listeners)) {
        listener.onSyncProgressEvent(SyncProgress()
          ..syncStatus = SyncStatus.success
          ..pendingPushCount = 0);
      }
      await waiting;

      expect(a.deleted, ['$bob:orphan0000000000.__ck.$namespace$alice']);
    });

    test('a collection refused mid-sync runs at the next caught-up sync',
        () async {
      final a = enrolled();
      await a.manager.ensureCurrent(a.context, shared());
      conveyance(a.store, 'orphan0000000000', cutBy: enrollmentId);
      final listeners = <SyncProgressListener>[];
      when(() => a.sync.addProgressListener(any()))
          .thenAnswer((inv) => listeners.add(inv.positionalArguments[0]));
      // Caught up by the event, but writes arrived before the check.
      when(() => a.sync.isInSync()).thenAnswer((_) async => false);
      void caughtUp() {
        for (final listener in List.of(listeners)) {
          listener.onSyncProgressEvent(SyncProgress()
            ..syncStatus = SyncStatus.success
            ..pendingPushCount = 0);
        }
      }

      final waiting =
          collectUnusedOnceCaughtUp(a.sync, () => a.manager, a.context);
      await Future<void>.delayed(Duration.zero);
      caughtUp();
      await a.manager.idle;
      await Future<void>.delayed(Duration.zero);
      expect(a.deleted, isEmpty, reason: 'the first pass is refused');

      when(() => a.sync.isInSync()).thenAnswer((_) async => true);
      caughtUp();
      await waiting;

      expect(a.deleted, ['$bob:orphan0000000000.__ck.$namespace$alice'],
          reason: 'a refusal waits for the next quiet moment, not the next '
              'start');
    });

    test('a replacement refused mid-sync collects at the next caught-up sync',
        () async {
      final a = enrolled();
      final listeners = <SyncProgressListener>[];
      when(() => a.sync.addProgressListener(any()))
          .thenAnswer((inv) => listeners.add(inv.positionalArguments[0]));
      await a.manager.ensureCurrent(a.context, shared());
      final superseded = a.cache.current(bob, namespace)!.ckKid;
      when(() => a.sync.isInSync()).thenAnswer((_) async => false);
      await a.manager.rotateContentKey(a.context, shared());
      await a.manager.idle;
      await Future<void>.delayed(Duration.zero);
      expect(a.deleted, isEmpty,
          reason: 'the cut\'s own writes are still waiting to push');

      when(() => a.sync.isInSync()).thenAnswer((_) async => true);
      for (final listener in List.of(listeners)) {
        listener.onSyncProgressEvent(SyncProgress()
          ..syncStatus = SyncStatus.success
          ..pendingPushCount = 0);
      }
      await Future<void>.delayed(Duration.zero);
      await a.manager.idle;

      expect(a.deleted.toSet(), conveyancesOf(superseded).toSet());
    });

    test('a service that stops before catching up collects nothing', () async {
      final a = enrolled();
      conveyance(a.store, 'orphan0000000000', cutBy: enrollmentId);
      final listeners = <SyncProgressListener>[];
      when(() => a.sync.addProgressListener(any()))
          .thenAnswer((inv) => listeners.add(inv.positionalArguments[0]));

      final waiting =
          collectUnusedOnceCaughtUp(a.sync, () => a.manager, a.context);
      await Future<void>.delayed(Duration.zero);
      for (final listener in List.of(listeners)) {
        listener.onSyncProgressEvent(SyncProgress()..stopped = true);
      }
      await waiting;

      expect(a.deleted, isEmpty);
    });
  });

  test('a pointer is read as the pipeline wrote it', () async {
    final a = enrolled();
    await a.manager.ensureCurrent(a.context, shared());
    final pointers =
        a.store.data.keys.where((k) => k.startsWith('__ckcur.')).toList();

    expect(pointers, ['__ckcur.bob.$namespace.$enrollmentId.a.__e$alice']);
    expect(jsonDecode(a.store.data[pointers.single]!.data!)['ckKid'],
        a.cache.current(bob, namespace)!.ckKid,
        reason: 'the fixture holds the pointer the collection reads');
  });
}
