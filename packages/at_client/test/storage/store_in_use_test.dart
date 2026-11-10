import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';
import 'package:test/test.dart';

import 'storage_contract.dart';

/// A Hive store another process holds is refused, naming where it is.
///
/// Catalogue: features/at_client/store_in_use.feature
void main() {
  test('A second process on a store in use is refused naming the store',
      () async {
    final dir = Directory.systemTemp.createTempSync('store_in_use_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final holder = await Process.start(Platform.resolvedExecutable,
        ['run', 'test/storage/hold_store.dart', dir.path]);
    addTearDown(holder.kill);
    final lines = holder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    expect(await lines.first.timeout(const Duration(seconds: 90)), 'held',
        reason: 'the control: the other process holds the store');

    final second = await Process.run(Platform.resolvedExecutable,
        ['run', 'test/storage/open_store.dart', dir.path]);

    expect('${second.stdout}'.trim().split('\n').last,
        'AtStorageInUseException ${dir.path}',
        reason: 'the second process is refused, naming the location: '
            '${second.stderr}');
  }, timeout: Timeout(Duration(minutes: 3)));

  test('A store that fails to open for another reason keeps its own error',
      () async {
    final dir = Directory.systemTemp.createTempSync('store_not_a_dir_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final notADirectory = File('${dir.path}/store')..writeAsStringSync('');

    final store = HiveAtClientStorage(
        atSign: '@holder'.toAtsign(), storagePath: notADirectory.path);
    await expectLater(store.attach(FakeClient('@holder', 'e1')),
        throwsA(isNot(isA<AtStorageInUseException>())));
  });
}
