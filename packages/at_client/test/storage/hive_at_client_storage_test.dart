import 'dart:io';

import 'package:at_client/hive.dart';
import 'package:at_client/src/storage/hive/hive_box_sync_queue_store.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show AtData;
import 'package:at_persistence_secondary_server/hive.dart' show HiveInstances;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('at_client_hive_'));
  tearDown(() => dir.deleteSync(recursive: true));

  runStorageContract('hive',
      (atSign) => HiveAtClientStorage(atSign: atSign, storagePath: dir.path),
      breakOpen: (atSign) =>
          unreadable('${dir.path}/${AtUtils.getShaForAtSign(atSign)}.hive'));

  test('a queue that fails to open leaves the keystore closed', () async {
    const atSign = '@hivequeue';
    final keystoreBox = AtUtils.getShaForAtSign(atSign);
    final first = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    await first.attach(FakeClient(atSign, 'e1'));
    await first.close();
    final restore = unreadable(
        '${dir.path}/${HiveBoxSyncQueueStore.boxNameFor(atSign)}.hive');
    if (restore == null) {
      markTestSkipped('the queue box cannot be made unreadable here');
      return;
    }
    addTearDown(restore);

    final s = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    await expectLater(
        s.attach(FakeClient(atSign, 'e1')), throwsA(isA<Exception>()));
    await pumpEventQueue();
    expect(HiveInstances.forPath(dir.path).isBoxOpen(keystoreBox), isFalse,
        reason: 'the keystore had opened before the queue failed; left open, '
            'the next store of this atSign wraps the same box a second time '
            'and the first wrapper is never closed');

    restore();
    final again = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    await again.attach(FakeClient(atSign, 'e1'));
    await again.keyStore.put('k$atSign', AtData()..data = 'v');
    expect((await again.keyStore.get('k$atSign'))?.data, 'v');
    await again.close();
  });
}
