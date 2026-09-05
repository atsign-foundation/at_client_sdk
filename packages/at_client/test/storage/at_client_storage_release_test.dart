import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

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
}
