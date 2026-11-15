// Contract every LocalRecordStore must satisfy. Each implementation's test
// file calls localRecordStoreContract with its own factory.

import 'package:at_client/src/storage/local_record_store.dart';
import 'package:at_commons/at_commons.dart';
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

    test(
        'update whose apply throws rethrows that error and keeps the prior value',
        () async {
      await store.put('local:a@alice', datum('v1'));
      final boom = StateError('apply failed');

      await expectLater(store.update('local:a@alice', (_) => throw boom),
          throwsA(same(boom)));

      expect((await store.get('local:a@alice'))!.data, 'v1');
    });

    test('metadata with null timestamps and version round-trips', () async {
      await store.put(
          'local:a@alice',
          AtData()
            ..data = 'v1'
            ..metaData = (AtMetaData()
              ..createdAt = null
              ..updatedAt = null
              ..version = null));

      final meta = (await store.get('local:a@alice'))!.metaData!;
      expect(meta.createdAt, isNull);
      expect(meta.updatedAt, isNull);
      expect(meta.version, isNull);
    });

    test(
        'metadata with encryption, expiry, pubKeyHash and appMetadata round-trips',
        () async {
      final expiresAt = DateTime.utc(2030, 1, 2, 3, 4, 5);
      await store.put(
          'local:a@alice',
          AtData()
            ..data = 'v1'
            ..metaData = (AtMetaData()
              ..isEncrypted = true
              ..expiresAt = expiresAt
              ..pubKeyHash = PublicKeyHash('hash-value', 'sha256')
              ..appMetadata = AppMetadata(
                  providerId: 'provider-x', additional: {'k': 'v'})));

      final meta = (await store.get('local:a@alice'))!.metaData!;
      expect(meta.isEncrypted, isTrue);
      expect(meta.expiresAt, expiresAt);
      expect(meta.pubKeyHash!.hash, 'hash-value');
      expect(meta.pubKeyHash!.hashingAlgo, 'sha256');
      expect(meta.appMetadata!.providerId, 'provider-x');
      expect(meta.appMetadata!.additional, {'k': 'v'});
    });
  });
}
