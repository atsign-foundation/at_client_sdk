import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

/// A storage whose [openBackend] can be held open on [gate], so a test can
/// interleave a second [attach] while the first is still inside it.
class _GatedStorage extends AtClientStorageBase {
  _GatedStorage(this._location, {Completer<void>? gate}) : _gate = gate;
  final String _location;
  final Completer<void>? _gate;

  @override
  String get location => _location;

  @override
  Future<void> openBackend() async {
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> closeBackend() async {}

  @override
  Future<void> clearData() async {}

  @override
  AtKeyValueStore<String, AtData, AtMetaData?> get keyStore =>
      throw UnimplementedError();

  @override
  AtSyncQueue get syncQueue => throw UnimplementedError();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('at_client_release_'));
  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    dir.deleteSync(recursive: true);
  });

  AtClientPreference pref() => AtClientPreference()
    ..hiveStoragePath = dir.path
    ..commitLogPath = '${dir.path}/commit';

  test(
      'a second storage for one atSign at the same location is refused; '
      'stop() releases it', () async {
    final first = await AtClientImpl.create('@releaseguard', 'wavi', pref())
        as AtClientImpl;
    final sameStore =
        HiveAtClientStorage(atSign: '@releaseguard', storagePath: dir.path);
    await expectLater(
        () => sameStore.attach(FakeClient('@releaseguard', 'e2')),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('already open at'))),
        reason: 'one directory and one atSign resolve to one Hive box, so '
            'these are one store however many objects point at it');

    await first.stop();
    await sameStore.attach(FakeClient('@releaseguard', 'e2'));
    expect(sameStore.isAttached, isTrue,
        reason: 'stop() closed the first storage, releasing the store');
    await sameStore.close();
  });

  test(
      'a second attach() racing the first cannot claim the same location '
      'before the first finishes opening', () async {
    final gate = Completer<void>();
    final first = _GatedStorage('@race-loc', gate: gate);
    final second = _GatedStorage('@race-loc');

    final firstAttach = first.attach(FakeClient('@race', 'e1'));
    // first is now suspended inside openBackend(), still awaiting gate.

    await expectLater(
        () => second.attach(FakeClient('@race', 'e2')),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('already open at'))),
        reason: 'the claim must be visible to a second attach() as soon as '
            'the first has passed its own checks, not only once the first '
            'has finished opening its backend — otherwise both attach and '
            'the loser\'s later close() tears down the backend the winner '
            'still uses');

    gate.complete();
    await firstAttach;
    expect(first.isAttached, isTrue);
    await first.close();
  });

  test('two storages for one atSign at different locations both open',
      () async {
    final other = Directory.systemTemp.createTempSync('at_client_release_b_');
    final here =
        HiveAtClientStorage(atSign: '@twoplaces', storagePath: dir.path);
    final there =
        HiveAtClientStorage(atSign: '@twoplaces', storagePath: other.path);
    await here.attach(FakeClient('@twoplaces', 'e1'));
    await there.attach(FakeClient('@twoplaces', 'e2'));
    expect(here.isAttached && there.isAttached, isTrue,
        reason: 'different directories are different Hive instances, so two '
            'enrollments of one atSign keep separate stores');
    expect(here.location, isNot(equals(there.location)));
    await here.close();
    await there.close();
    other.deleteSync(recursive: true);
  });

  test('two atSigns sharing one directory both open', () async {
    final a = HiveAtClientStorage(atSign: '@shareda', storagePath: dir.path);
    final b = HiveAtClientStorage(atSign: '@sharedb', storagePath: dir.path);
    await a.attach(FakeClient('@shareda', 'e1'));
    await b.attach(FakeClient('@sharedb', 'e1'));
    expect(a.isAttached && b.isAttached, isTrue,
        reason: 'the box name derives from the atSign, so two atSigns under '
            'one directory are two boxes and share nothing');
    await a.close();
    await b.close();
  });

  test(
      'a fresh create() after stop() gets a new client on freshly opened '
      'storage', () async {
    final first = await AtClientImpl.create('@releasefresh', 'wavi', pref())
        as AtClientImpl;
    final firstStorage = first.storage;
    await first.stop();
    final again = await AtClientImpl.create('@releasefresh', 'wavi', pref())
        as AtClientImpl;
    expect(identical(again, first), isFalse,
        reason: 'the stopped client left the instance map');
    expect(identical(again.storage, firstStorage), isFalse,
        reason: 'and its storage was closed rather than handed on');
    expect(again.isStopped, isFalse);
  });

  test('a client whose construction fails releases the storage it claimed',
      () async {
    final bad = pref()
      ..crypto = const CryptoConfig(defaultProviderId: 'no-such-provider');
    await expectLater(AtClientImpl.create('@releasefail', 'wavi', bad),
        throwsA(isA<Exception>()),
        reason: 'the default provider is not registered, so create() throws '
            'after the storage was attached');
    final ok = await AtClientImpl.create('@releasefail', 'wavi', pref())
        as AtClientImpl;
    expect(ok.storage, isNotNull,
        reason: 'a failed build must not leave its claim behind, or no client '
            'for that atSign could ever be built in this isolate again');
  });

  test(
      'a client uses the storage it is given, and stop() does not close what '
      'it does not own', () async {
    final injected = InMemoryAtClientStorage(atSign: '@injected');
    // No hiveStoragePath: supplying storage picks the backend AND the
    // location, so the preference no longer has to name one.
    final client = await AtClientImpl.create(
            '@injected', 'wavi', AtClientPreference(), storage: injected)
        as AtClientImpl;

    expect(identical(client.storage, injected), isTrue,
        reason: 'the client used the storage it was handed rather than '
            'building a Hive one from the preference');

    await client.stop();

    expect(injected.isAttached, isFalse, reason: 'stop() dropped the claim');
    await injected.attach(FakeClient('@injected', null));
    expect(injected.isAttached, isTrue,
        reason: 'an injected store outlives the client that borrowed it - the '
            'caller owns its lifetime, so stop() must not have closed it');
    await injected.close();
  });

  test('a client with no injected storage still owns and closes its own',
      () async {
    final client =
        await AtClientImpl.create('@ownsits', 'wavi', pref()) as AtClientImpl;
    final own = client.storage!;
    await client.stop();
    await expectLater(() => own.attach(FakeClient('@ownsits', null)),
        throwsA(isA<StateError>()),
        reason: 'storage the client built itself is closed on release, and a '
            'closed store cannot be reopened');
  });
}
