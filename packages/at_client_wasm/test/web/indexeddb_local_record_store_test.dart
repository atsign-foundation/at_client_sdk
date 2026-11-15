@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:at_client_wasm/at_client_wasm_web.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import '../local_record_store_contract.dart';

AtData datum(String data, {int? ttl}) => AtData()
  ..data = data
  ..metaData = (AtMetaData()..ttl = ttl);

void main() {
  String generateDbName() =>
      'test_local_db_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond).toString()}';

  Future<void> deleteDb(String name) async {
    final completer = Completer<void>();
    final request = window.indexedDB.deleteDatabase(name);
    request.onsuccess = (Event e) {
      completer.complete();
    }.toJS;
    request.onerror = (Event e) {
      completer.completeError(Exception('Failed to delete DB'));
    }.toJS;
    await completer.future;
  }

  group('IndexedDbLocalRecordStore contract', () {
    String? currentDbName;
    List<IndexedDbLocalRecordStore> openStores = [];

    setUp(() {
      currentDbName = generateDbName();
      openStores = [];
    });

    tearDown(() async {
      for (final store in openStores) {
        await store.close();
      }
      if (currentDbName != null) {
        await deleteDb(currentDbName!);
      }
    });

    localRecordStoreContract('IndexedDbLocalRecordStore', () async {
      final store = await IndexedDbLocalRecordStore.open(
          atSign: '@alice', enrollmentId: 'e1', dbName: currentDbName!);
      openStores.add(store);
      return store;
    });
  });

  group('IndexedDbLocalRecordStore extras', () {
    String? currentDbName;
    List<IndexedDbLocalRecordStore> openStores = [];
    List<String> defaultDbNames = [];

    setUp(() {
      currentDbName = generateDbName();
      openStores = [];
      defaultDbNames = [];
    });

    tearDown(() async {
      for (final store in openStores) {
        await store.close();
      }
      for (final name in [
        ...defaultDbNames,
        if (currentDbName != null) currentDbName!
      ]) {
        await deleteDb(name);
      }
    });

    Future<IndexedDbLocalRecordStore> open() async {
      final store = await IndexedDbLocalRecordStore.open(
          atSign: '@alice', enrollmentId: 'e1', dbName: currentDbName!);
      openStores.add(store);
      return store;
    }

    test('data and metaData ttl survive close and reopen', () async {
      final first = await open();
      await first.put('local:a@alice', datum('v1', ttl: 5000));
      await first.close();
      openStores.clear();

      final reopened = await open();
      final got = await reopened.get('local:a@alice');

      expect(got!.data, 'v1');
      expect(got.metaData!.ttl, 5000);
    });

    test('close() closes the connection, so later calls throw', () async {
      final store = await open();
      await store.put('local:a@alice', datum('v1'));
      await store.close();

      await expectLater(store.get('local:a@alice'), throwsA(anything));
    });

    test('a database whose store is still open can be deleted', () async {
      final store = await open();
      await store.put('local:a@alice', datum('v1'));

      await deleteDb(currentDbName!);
    });

    test('default db names differ per enrollmentId and hide each other\'s data',
        () async {
      final e1 = await IndexedDbLocalRecordStore.open(
          atSign: '@alice', enrollmentId: 'e1');
      final e2 = await IndexedDbLocalRecordStore.open(
          atSign: '@alice', enrollmentId: 'e2');
      openStores
        ..add(e1)
        ..add(e2);
      defaultDbNames = [e1.dbName, e2.dbName];

      expect(e1.dbName, isNot(e2.dbName));
      expect(e1.dbName, 'atclient-local:@alice:e1');

      await e1.put('local:a@alice', datum('only-e1'));

      expect(await e2.get('local:a@alice'), isNull);
      expect(await e2.keys(), isEmpty);
    });

    test(
        'concurrent update() from two instances over one DB loses no increments',
        () async {
      final a = await open();
      final b = await IndexedDbLocalRecordStore.open(
          atSign: '@alice', enrollmentId: 'e1', dbName: currentDbName!);
      openStores.add(b);

      int bump(AtData? current) => int.parse(current?.data ?? '0') + 1;

      await Future.wait([
        for (var i = 0; i < 20; i++)
          a.update('local:counter@alice', (c) => datum('${bump(c)}')),
        for (var i = 0; i < 20; i++)
          b.update('local:counter@alice', (c) => datum('${bump(c)}')),
      ]);

      expect((await a.get('local:counter@alice'))!.data, '40');
    });
  });
}
