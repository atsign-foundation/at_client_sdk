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
      'while a client holds an atSign\'s Hive storage, a second storage for '
      'that atSign is refused; after stop() it is allowed', () async {
    final first = await AtClientImpl.create('@releaseguard', 'wavi', pref())
        as AtClientImpl;
    final other = Directory.systemTemp.createTempSync('at_client_release_b_');
    final second =
        HiveAtClientStorage(atSign: '@releaseguard', storagePath: other.path);
    await expectLater(
        () => second.attach(FakeClient('@releaseguard', 'e2')),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('already holds @releaseguard'))),
        reason: 'every box is on the global Hive instance and named by atSign, '
            'so a second path is not a second store');

    await first.stop();
    await second.attach(FakeClient('@releaseguard', 'e2'));
    expect(second.isAttached, isTrue,
        reason: 'stop() closed the first storage, so the atSign is free');
    await second.close();
    other.deleteSync(recursive: true);
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
