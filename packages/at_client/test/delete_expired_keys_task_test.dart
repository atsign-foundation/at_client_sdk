import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_persistence.dart';

class MockCommitLog extends Mock implements ClientAtCommitLog {}

void main() {
  var storageDir = '${Directory.current.path}/test/hive';
  String atsign = '@expiry_test';
  var commitLog = MockCommitLog();
  late TestPersistence persistence;
  late AtPersistenceBundle bundle;

  group('validate behaviour of scheduled deleteExpiredKeys task', () {
    when(() => commitLog.commit(any(), CommitOp.UPDATE_ALL))
        .thenAnswer((_) => Future.value(1));

    when(() => commitLog.commit(any(), CommitOp.DELETE))
        .thenAnswer((_) => Future.value(2));

    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atsign);
      persistence = TestPersistence(storageDir);
      bundle = await persistence.init(atsign);
      bundle.keyStore.commitLog = commitLog;
    });

    test('verify that delete expired keys task removes expired keys', () async {
      String key1 = 'public:expired_key_1.test$atsign';
      AtMetaData metadata = AtMetaData()..ttl = 1;
      AtData data = AtData()
        ..data = 'data_key_1'
        ..metaData = metadata;
      await bundle.keyStore.put(key1, data);

      String key2 = 'public:expired_key_2.test$atsign';
      data = AtData()
        ..data = 'data_key_2'
        ..metaData = metadata;
      await bundle.keyStore.put(key2, data);

      String key3 = 'public:unexpired_key_3.test$atsign';
      metadata.ttl = 1000000;
      data = AtData()
        ..data = 'data_key_3'
        ..metaData = metadata;
      await bundle.keyStore.put(key3, data);

      await bundle.keyStore.deleteExpiredKeys();

      int exceptionCatchCount = 0;
      try {
        await bundle.keyStore.get(key1);
      } on Exception catch (e) {
        expect(e.toString().contains('$key1 does not exist in keystore'), true);
        exceptionCatchCount++;
      }

      try {
        await bundle.keyStore.get(key2);
      } on Exception catch (e) {
        expect(e.toString().contains('$key2 does not exist in keystore'), true);
        exceptionCatchCount++;
      }

      expect((await bundle.keyStore.get(key3))?.data, 'data_key_3');
      expect(exceptionCatchCount,
          2); // this counter maintains the count of how many exceptions have been caught
    });

    tearDown(() async {
      await persistence.tearDown();
    });
  });
}
