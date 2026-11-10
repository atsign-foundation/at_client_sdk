// Contract every LocalRecordStore must satisfy. Each implementation's test
// file calls localRecordStoreContract with its own factory.

import 'package:at_client/src/storage/local_record_store.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

void localRecordStoreContract(
    String name, Future<LocalRecordStore> Function() make) {
  group(name, () {
    late LocalRecordStore store;

    setUp(() async {
      store = await make();
    });

    AtData datum(String data, {int? ttl}) => AtData()
      ..data = data
      ..metaData = (AtMetaData()..ttl = ttl);

    test('get of an absent key returns null', () async {
      expect(await store.get('local:absent@alice'), isNull);
    });

    test('put then get returns the same data and metadata', () async {
      await store.put('local:a@alice', datum('v1', ttl: 5000));

      final got = await store.get('local:a@alice');
      expect(got!.data, 'v1');
      expect(got.metaData!.ttl, 5000);
    });

    test('put overwrites the existing value', () async {
      await store.put('local:a@alice', datum('v1'));
      await store.put('local:a@alice', datum('v2'));

      expect((await store.get('local:a@alice'))!.data, 'v2');
    });

    test('remove then get returns null', () async {
      await store.put('local:a@alice', datum('v1'));
      await store.remove('local:a@alice');

      expect(await store.get('local:a@alice'), isNull);
    });

    test('keys lists put keys and omits removed ones', () async {
      await store.put('local:a@alice', datum('1'));
      await store.put('local:b@alice', datum('2'));
      await store.remove('local:a@alice');

      expect(await store.keys(), ['local:b@alice']);
    });

    test('update on an absent key passes null and stores the result', () async {
      AtData? seen = AtData()..data = 'sentinel';
      final result = await store.update('local:a@alice', (current) {
        seen = current;
        return datum('created');
      });

      expect(seen, isNull);
      expect(result!.data, 'created');
      expect((await store.get('local:a@alice'))!.data, 'created');
    });

    test('update passes the current value and stores the result', () async {
      await store.put('local:a@alice', datum('v1'));

      final result = await store.update(
          'local:a@alice', (current) => datum('${current!.data}+1'));

      expect(result!.data, 'v1+1');
      expect((await store.get('local:a@alice'))!.data, 'v1+1');
    });

    test('update returning null removes the key', () async {
      await store.put('local:a@alice', datum('v1'));

      final result = await store.update('local:a@alice', (_) => null);

      expect(result, isNull);
      expect(await store.get('local:a@alice'), isNull);
      expect(await store.keys(), isEmpty);
    });

    test('update returns the value it stored', () async {
      final result =
          await store.update('local:a@alice', (_) => datum('stored', ttl: 9));

      expect(result!.data, 'stored');
      expect(result.metaData!.ttl, 9);
    });
  });
}
