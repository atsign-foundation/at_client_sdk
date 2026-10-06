import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('at_client_hive_'));
  tearDown(() => dir.deleteSync(recursive: true));

  runStorageContract('hive',
      (atSign) => HiveAtClientStorage(atSign: atSign, storagePath: dir.path));

  test('a keystore that cannot be read fails the open once, to the caller',
      () async {
    if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
      markTestSkipped('root reads a file whatever its mode says');
      return;
    }
    const atSign = '@hiveunreadable';
    final first = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    await first.attach(FakeClient(atSign, 'e1'));
    await first.close();
    final keystore =
        File('${dir.path}/${AtUtils.getShaForAtSign(atSign)}.hive');
    expect(Process.runSync('chmod', ['000', keystore.path]).exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['600', keystore.path]));

    final store = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    addTearDown(store.close);
    await expectLater(store.attach(FakeClient(atSign, 'e1')),
        throwsA(isA<DataStoreException>()));
    // NOTE: an unhandled second report would arrive after the caller's, and
    // fails this test only if it lands before the test ends.
    await pumpEventQueue();

    expect(Process.runSync('chmod', ['600', keystore.path]).exitCode, 0);
    await store.attach(FakeClient(atSign, 'e1'));
    await store.keyStore.put('phone.wavi$atSign', AtData()..data = 'value');
    expect((await store.keyStore.get('phone.wavi$atSign'))?.data, 'value',
        reason: 'the failure left nothing behind that stops a later open');
  });
}
