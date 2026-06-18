import 'dart:io';

import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:test/test.dart';

void main() {
  final storagePath = '${Directory.current.path}/test/hive';
  const atsign = '@expiry_test';

  late HiveAtPersistenceFactory factory;
  late AtKeyValueStore<String, AtData, AtMetaData?> keyStore;

  group('validate behaviour of the deleteExpiredKeys task', () {
    setUp(() async {
      factory = HiveAtPersistenceFactory();
      final bundle = await factory.initialize(atsign,
          HivePersistenceConfig.clientDefaults(storagePath: storagePath));
      keyStore = bundle.keyValueStore;
    });

    tearDown(() async {
      await factory.close();
      final dir = Directory(storagePath);
      if (await dir.exists()) dir.deleteSync(recursive: true);
    });

    test('verify that delete expired keys task removes expired keys', () async {
      final key1 = 'public:expired_key_1.test$atsign';
      await keyStore.put(
          key1,
          AtData()
            ..data = 'data_key_1'
            ..metaData = (AtMetaData()..ttl = 1));

      final key2 = 'public:expired_key_2.test$atsign';
      await keyStore.put(
          key2,
          AtData()
            ..data = 'data_key_2'
            ..metaData = (AtMetaData()..ttl = 1));

      final key3 = 'public:unexpired_key_3.test$atsign';
      await keyStore.put(
          key3,
          AtData()
            ..data = 'data_key_3'
            ..metaData = (AtMetaData()..ttl = 1000000));

      // Allow time for the ttl==1 records to expire.
      await Future.delayed(Duration(milliseconds: 5));

      await keyStore.deleteExpiredKeys();

      expect(await keyStore.exists(key1), false);
      expect(await keyStore.exists(key2), false);
      expect((await keyStore.get(key3))?.data, 'data_key_3');
    });
  });
}
