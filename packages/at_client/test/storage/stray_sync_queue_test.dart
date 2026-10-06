import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:hive/hive.dart';
// ignore: implementation_imports
import 'package:hive/src/hive_impl.dart';
import 'package:test/test.dart';

import 'storage_contract.dart' show FakeClient;

/// A sync queue an earlier release opened on Hive's global instance can sit in
/// a directory other than its atSign's store, and is taken in when that
/// atSign's store opens.
void main() {
  late Directory root;
  final opened = <HiveAtClientStorage>[];

  setUp(() => root = Directory.systemTemp.createTempSync('stray_queue_'));

  tearDown(() async {
    for (final s in opened) {
      await s.close();
    }
    opened.clear();
    root.deleteSync(recursive: true);
  });

  String dirFor(String name) =>
      (Directory('${root.path}/$name')..createSync()).path;

  Future<HiveAtClientStorage> open(String atSign, String directory) async {
    final s = HiveAtClientStorage(atSign: atSign, storagePath: directory);
    opened.add(s);
    await s.attach(FakeClient(atSign, 'e1'));
    return s;
  }

  Future<void> close(HiveAtClientStorage s) async {
    opened.remove(s);
    await s.close();
  }

  /// Opens [atSign]'s store in [directory], files [records] in its keystore
  /// and closes it, as a store an earlier session wrote.
  Future<void> storeHolding(
      String atSign, String directory, List<String> records) async {
    final s = await open(atSign, directory);
    for (final key in records) {
      await s.keyStore.put(key, AtData()..data = 'value');
    }
    await close(s);
  }

  String queueFile(String atSign, String directory) =>
      '$directory/${AtSyncQueue.boxNameForAtSign(atSign)}.hive';

  /// Leaves [atSign]'s queue box in [directory] holding [entries], as the
  /// earlier release wrote one on Hive's global instance.
  Future<void> leaveStrayQueue(
      String atSign, String directory, Map<String, String> entries) async {
    final hive = HiveImpl()..init(directory);
    final box =
        await hive.openBox<String>(AtSyncQueue.boxNameForAtSign(atSign));
    await box.putAll(entries);
    await box.close();
  }

  // NOTE: the at-rest form at_client 3.14.0 wrote its queue entries in.
  const updateWritten = '{"op":"update","ts":1000}';
  const deleteWritten = '{"op":"delete","ts":1000}';

  test('a queue left in another atSign\'s store is taken in', () async {
    const alice = '@strayalice';
    final mine = dirFor('alice');
    final theirs = dirFor('bob');
    await close(await open('@straybob', theirs));
    await storeHolding(alice, mine, ['phone.wavi$alice']);
    await leaveStrayQueue(alice, theirs, {'phone.wavi$alice': updateWritten});
    expect(File(queueFile(alice, theirs)).existsSync(), isTrue,
        reason: 'the control: the stray is where the earlier release left it');

    final store = await open(alice, mine);

    expect(store.syncQueue.peek(), ['phone.wavi$alice'],
        reason: 'the write was still to be pushed when the earlier release '
            'stopped, and its record is in this store');
    expect(
        store.syncQueue.readEntry('phone.wavi$alice')?.op, SyncQueueOp.update);
    expect(File(queueFile(alice, theirs)).existsSync(), isFalse,
        reason: 'taken in once, so it is not taken in again');
  });

  test('a queue left in the directory the app gave Hive is taken in', () async {
    const alice = '@strayappalice';
    final mine = dirFor('alice');
    final apps = dirFor('app');
    await storeHolding(alice, mine, ['phone.wavi$alice']);
    await leaveStrayQueue(alice, apps, {'phone.wavi$alice': updateWritten});
    Hive.init(apps);

    final store = await open(alice, mine);

    expect(store.syncQueue.peek(), ['phone.wavi$alice']);
    expect(File(queueFile(alice, apps)).existsSync(), isFalse);
  });

  test('a store that opens holding another atSign\'s stray queue hands it on',
      () async {
    const alice = '@strayhandalice';
    final mine = dirFor('alice');
    final theirs = dirFor('bob');
    await storeHolding(alice, mine, ['phone.wavi$alice']);
    final store = await open(alice, mine);
    await leaveStrayQueue(alice, theirs, {'phone.wavi$alice': updateWritten});
    expect(store.syncQueue.peek(), isEmpty);

    await open('@strayhandbob', theirs);

    expect(store.syncQueue.peek(), ['phone.wavi$alice'],
        reason: 'the directory was opened only after this atSign\'s store, '
            'so the store opening there is the one that finds it');
    expect(File(queueFile(alice, theirs)).existsSync(), isFalse);
  });

  test('a queue beside its own keystore is another store, and is left alone',
      () async {
    const alice = '@straytwoalice';
    final mine = dirFor('alice');
    final second = dirFor('second');
    final other = await open(alice, second);
    await other.keyStore.put('phone.wavi$alice', AtData()..data = 'value');
    await other.syncQueue.enqueue('phone.wavi$alice', SyncQueueOp.update);
    await close(other);

    final store = await open(alice, mine);

    expect(store.syncQueue.peek(), isEmpty,
        reason: 'a second store of one atSign keeps its own queue');
    expect(File(queueFile(alice, second)).existsSync(), isTrue);
  });

  test('an entry the keystore no longer agrees with is not taken', () async {
    const alice = '@straystalealice';
    final mine = dirFor('alice');
    final theirs = dirFor('bob');
    await close(await open('@straystalebob', theirs));
    await storeHolding(alice, mine, ['kept.wavi$alice']);
    await leaveStrayQueue(alice, theirs, {
      'gone.wavi$alice': updateWritten,
      'kept.wavi$alice': deleteWritten,
    });

    final store = await open(alice, mine);

    expect(store.syncQueue.peek(), isEmpty,
        reason: 'an update for a record since deleted, and a delete for one '
            'since written again, would each push a state this store no '
            'longer has');
    expect(File(queueFile(alice, theirs)).existsSync(), isFalse);
  });

  test('a newer entry already queued here stays', () async {
    const alice = '@straynewalice';
    final mine = dirFor('alice');
    final theirs = dirFor('bob');
    await close(await open('@straynewbob', theirs));
    final first = await open(alice, mine);
    await first.keyStore.put('phone.wavi$alice', AtData()..data = 'value');
    await first.syncQueue
        .enqueue('phone.wavi$alice', SyncQueueOp.updateAll, ts: 2000);
    await close(first);
    await leaveStrayQueue(alice, theirs, {'phone.wavi$alice': updateWritten});

    final store = await open(alice, mine);

    expect(store.syncQueue.readEntry('phone.wavi$alice')?.op,
        SyncQueueOp.updateAll);
    expect(store.syncQueue.readEntry('phone.wavi$alice')?.ts, 2000);
  });
}
