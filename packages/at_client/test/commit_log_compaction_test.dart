import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/compaction/at_commit_log_compaction.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtCompactionJob extends Mock implements AtCompactionJob {}

String currentAtSign = '@alice';
late SecondaryPersistenceStore secondaryPersistenceStore;
String storageDir = '${Directory.current.path}/test/hive';

void main() {
  group('A group of tests to verify getCompactionStats', () {
    test(
        'A test to verify default compaction stats are returned when stats key is not available',
        () async {
      SecondaryKeyStore mockSecondaryKeyStore = MockSecondaryKeyStore();
      AtClientManager mockAtClientManager = MockAtClientManager();
      AtCompactionJob mockAtCompactionJob = MockAtCompactionJob();

      when(() => mockSecondaryKeyStore.isKeyExists(commitLogCompactionKey))
          .thenAnswer((_) => false);
      AtClientCommitLogCompaction atClientCommitLogCompaction =
          AtClientCommitLogCompaction.create(
              mockAtClientManager, mockAtCompactionJob);
      atClientCommitLogCompaction.secondaryKeyStore = mockSecondaryKeyStore;

      AtCompactionStats atCompactionStats =
          await atClientCommitLogCompaction.getCompactionStats();
      expect(atCompactionStats.deletedKeysCount, -1);
      expect(atCompactionStats.postCompactionEntriesCount, -1);
      expect(atCompactionStats.preCompactionEntriesCount, -1);
      expect(atCompactionStats.compactionDurationInMills, -1);
      expect(atCompactionStats.atCompactionType, 'AtCommitLog');
    });

    test(
        'A test to verify getCompactionStats when compaction stats key is available',
        () async {
      SecondaryKeyStore mockSecondaryKeyStore = MockSecondaryKeyStore();
      AtClientManager mockAtClientManager = MockAtClientManager();
      AtCompactionJob mockAtCompactionJob = MockAtCompactionJob();

      when(() => mockSecondaryKeyStore.isKeyExists(commitLogCompactionKey))
          .thenAnswer((_) => true);
      when(() => mockSecondaryKeyStore.get(commitLogCompactionKey))
          .thenAnswer((_) async => Future.value(AtData()
            ..data = jsonEncode({
              'atCompactionType': 'AtCommitLog',
              'lastCompactionRun': '2022-12-19 10:30:00.000',
              'compactionDurationInMills': '1000',
              'preCompactionEntriesCount': '10',
              'postCompactionEntriesCount': '5',
              'deletedKeysCount': '5'
            })));
      AtClientCommitLogCompaction atClientCommitLogCompaction =
          AtClientCommitLogCompaction.create(
              mockAtClientManager, mockAtCompactionJob);
      atClientCommitLogCompaction.secondaryKeyStore = mockSecondaryKeyStore;

      AtCompactionStats atCompactionStats =
          await atClientCommitLogCompaction.getCompactionStats();
      expect(atCompactionStats.deletedKeysCount, 5);
      expect(atCompactionStats.postCompactionEntriesCount, 5);
      expect(atCompactionStats.preCompactionEntriesCount, 10);
      expect(atCompactionStats.compactionDurationInMills, 1000);
      expect(atCompactionStats.atCompactionType, 'AtCommitLog');
    });
  });
}
