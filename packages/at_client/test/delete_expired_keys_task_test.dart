import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockCommitLog extends Mock implements ClientAtCommitLog {}

void main() {
  var storagePath = '${Directory.current.path}/test/hive';
  String atsign = '@expiry_test';
  var commitLog = MockCommitLog();

  group('validate behaviour of scheduled deleteExpiredKeys task', () {
    when(() => commitLog.commit(any(), CommitOp.UPDATE_ALL))
        .thenAnswer((_) => Future.value(1));

    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atsign);
      await setUpStorage(atsign, storagePath, commitLog);
    });

    test('verify that delete expired keys task removes expired keys', () async {
      String key1 = 'public:expired_key_1.test$atsign';
      AtMetaData metadata = AtMetaData()..ttl = 1000;
      AtData data = AtData()
        ..data = 'data_key_1'
        ..metaData = metadata;
      await getKeyStore(atsign)?.put(key1, data);

      String key2 = 'public:expired_key_2.test$atsign';
      data = AtData()
        ..data = 'data_key_2'
        ..metaData = metadata;
      await getKeyStore(atsign)?.put(key2, data);

      String key3 = 'public:unexpired_key_3.test$atsign';
      metadata.ttl = -1;
      data = AtData()
        ..data = 'data_key_3'
        ..metaData = metadata;
      await getKeyStore(atsign)?.put(key3, data);

      SecondaryPersistenceStoreFactory.getInstance()
          .getSecondaryPersistenceStore(atsign)
          ?.getHivePersistenceManager()
          ?.scheduleKeyExpireTask(1);

      stdout.writeln('Sleeping for 1min 10s');
      await Future.delayed(Duration(minutes: 1, seconds: 10));

      expect(await getKeyStore(atsign)?.get(key1),
          throwsA(predicate((e) => e is KeyNotFoundException)));

      expect(await getKeyStore(atsign)?.get(key2),
          throwsA(predicate((e) => e is KeyNotFoundException)));

      expect((await getKeyStore(atsign)?.get(key3))?.data, 'data_key_3');
    }, timeout: Timeout(Duration(minutes: 2)));

    tearDown(() async {
      await tearDownLocalStorage(storagePath);
    });
  });
}

HiveKeystore? getKeyStore(String atsign) {
  return SecondaryPersistenceStoreFactory.getInstance()
      .getSecondaryPersistenceStore(atsign)
      ?.getSecondaryKeyStore();
}

Future<void> setUpStorage(String atsign, String storagePath, ClientAtCommitLog commitLog) async {
  var manager = SecondaryPersistenceStoreFactory.getInstance()
      .getSecondaryPersistenceStore(atsign);
  await manager?.getHivePersistenceManager()?.init(storagePath);
  manager?.getSecondaryKeyStore()?.commitLog = commitLog;
}

Future<void> tearDownLocalStorage(storageDir) async {
  try {
    var isExists = await Directory(storageDir).exists();
    if (isExists) {
      Directory(storageDir).deleteSync(recursive: true);
    }
  } catch (e, st) {
    print('local_secondary_test.dart: exception / error in tearDown: $e, $st');
  }
}
