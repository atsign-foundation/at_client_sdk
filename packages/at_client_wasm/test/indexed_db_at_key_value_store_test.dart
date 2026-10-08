// ignore_for_file: implementation_imports
import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client_wasm/src/storage/indexed_db_at_client_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  int counter = 0;
  String nextEnrollmentId() =>
      'e${counter++}_${DateTime.now().millisecondsSinceEpoch}';

  final opened = <(IndexedDbAtClientStorage, String)>[];

  tearDown(() async {
    for (final (s, e) in opened) {
      await s.closeBackend();
      await IndexedDbAtClientStorage.deleteDatabase(
          atSign: '@alice', enrollmentId: e);
    }
    opened.clear();
  });

  Future<IndexedDbAtClientStorage> setupStore() async {
    final e = nextEnrollmentId();
    final s = IndexedDbAtClientStorage(atSign: '@alice', enrollmentId: e);
    await s.openBackend();
    opened.add((s, e));
    return s;
  }

  group('parity group', () {
    test('missing get throws KeyNotFoundException and getMeta returns null',
        () async {
      final s = await setupStore();
      final store = s.keyStore;

      await expectLater(
          store.get('missing@alice'), throwsA(isA<KeyNotFoundException>()));
      expect(await store.getMeta('missing@alice'), isNull);
    });

    test('concurrent puts to one new key: one KeyAdded, one KeyUpdated',
        () async {
      final s = await setupStore();
      final store = s.keyStore;
      final events = <KeyStoreChange>[];
      final sub = store.changes.listen(events.add);

      await Future.wait([
        store.put('race@alice', AtData()..data = 'a'),
        store.put('race@alice', AtData()..data = 'b'),
      ]);
      await Future.delayed(Duration.zero);

      expect(events.map((e) => e.runtimeType),
          unorderedEquals([KeyAdded, KeyUpdated]));
      await sub.cancel();
    });

    test('removeMany counts and emits only keys that existed', () async {
      final s = await setupStore();
      final store = s.keyStore;
      await store.put('a@alice', AtData()..data = 'a');
      final events = <KeyStoreChange>[];
      final sub = store.changes.listen(events.add);

      expect(await store.removeMany(['a@alice', 'ghost@alice']), 1);
      await Future.delayed(Duration.zero);

      expect(
          events.map((e) => (e.runtimeType, e.key)), [(KeyRemoved, 'a@alice')]);
      await sub.cancel();
    });

    test('put-new then put-existing emits KeyAdded then KeyUpdated', () async {
      final s = await setupStore();
      final store = s.keyStore;

      final events = <KeyStoreChange>[];
      final sub = store.changes.listen(events.add);

      await store.put('k1@alice', AtData()..data = 'v1');
      await store.put('k1@alice', AtData()..data = 'v2');

      await Future.delayed(Duration.zero);
      expect(events[0], isA<KeyAdded>());
      expect(events[0].key, 'k1@alice');
      expect(events[1], isA<KeyUpdated>());
      expect(events[1].key, 'k1@alice');

      await sub.cancel();
    });

    test('remove emits KeyRemoved and runs the hooks', () async {
      final s = await setupStore();
      final store = s.keyStore;

      var preFired = false;
      var postFired = false;

      store.preRemoveHooks.add((k, {required skipCommit}) async {
        preFired = true;
      });
      store.postRemoveHooks.add((k, {required skipCommit}) async {
        postFired = true;
      });

      await store.put('k1@alice', AtData()..data = 'v1');

      final events = <KeyStoreChange>[];
      final sub = store.changes.listen(events.add);

      await store.remove('k1@alice');

      await Future.delayed(Duration.zero);
      expect(events[0], isA<KeyRemoved>());
      expect(preFired, isTrue);
      expect(postFired, isTrue);

      await sub.cancel();
    });

    test(
        'getKeys(regex:) filters, and hides a key with ttl expired and one with ttb in the future',
        () async {
      final s = await setupStore();
      final store = s.keyStore;

      await store.put('k1.test@alice', AtData()..data = 'v1');
      await store.put(
          'k2.test@alice',
          AtData()
            ..data = 'v2'
            ..metaData = (AtMetaData()
              ..expiresAt = DateTime.now().subtract(Duration(seconds: 1))));
      await store.put(
          'k3.test@alice',
          AtData()
            ..data = 'v3'
            ..metaData = (AtMetaData()
              ..availableAt = DateTime.now().add(Duration(days: 1))));
      await store.put('k4.other@alice', AtData()..data = 'v4');

      final stream = await store.getKeys(regex: r'\.test');
      final keys = await stream.toList();

      expect(keys, contains('k1.test@alice'));
      expect(keys, isNot(contains('k2.test@alice')));
      expect(keys, isNot(contains('k3.test@alice')));
      expect(keys, isNot(contains('k4.other@alice')));
    });

    test('a bad regex fails the Future', () async {
      final s = await setupStore();
      final store = s.keyStore;

      await expectLater(
          store.getKeys(regex: '['), throwsA(isA<FormatException>()));
    });

    test('getExpiredKeys / deleteExpiredKeys / nextExpiresAt / nextAvailableAt',
        () async {
      final s = await setupStore();
      final store = s.keyStore;

      final d1 = DateTime.now().subtract(Duration(seconds: 10));
      final d2 = DateTime.now().add(Duration(seconds: 10));

      await store.put(
          'k1@alice',
          AtData()
            ..data = '1'
            ..metaData = (AtMetaData()..expiresAt = d1));
      await store.put(
          'k2@alice',
          AtData()
            ..data = '2'
            ..metaData = (AtMetaData()..expiresAt = d2));
      await store.put(
          'k3@alice',
          AtData()
            ..data = '3'
            ..metaData = (AtMetaData()..availableAt = d1));
      await store.put(
          'k4@alice',
          AtData()
            ..data = '4'
            ..metaData = (AtMetaData()..availableAt = d2));

      final expired = await (await store.getExpiredKeys()).toList();
      expect(expired, ['k1@alice']);

      expect((await store.nextExpiresAt())?.millisecondsSinceEpoch,
          d1.toUtc().millisecondsSinceEpoch);
      expect(
          (await store.nextAvailableAt(
                  asOf: DateTime.now().subtract(Duration(days: 1))))
              ?.millisecondsSinceEpoch,
          d1.toUtc().millisecondsSinceEpoch);

      await store.deleteExpiredKeys();
      expect(await store.exists('k1@alice'), isFalse);
      expect(await store.exists('k2@alice'), isTrue);
    });

    test(
        'an over-long key is rejected with the same exception type SQLite uses',
        () async {
      final s = await setupStore();
      final store = s.keyStore;

      final longKey = '${List.filled(300, 'a').join()}@alice';
      await expectLater(store.put(longKey, AtData()..data = 'v'),
          throwsA(isA<DataStoreException>()));
    });

    test('putMeta updates metadata only', () async {
      final s = await setupStore();
      final store = s.keyStore;

      await store.put(
          'k1@alice',
          AtData()
            ..data = 'v'
            ..metaData = (AtMetaData()..ttl = 100));
      await store.putMeta('k1@alice', AtMetaData()..ttl = 200);

      final read = await store.get('k1@alice');
      expect(read?.data, 'v');
      expect(read?.metaData?.ttl, 200);
    });
  });
}
