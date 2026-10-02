import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/hive.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_client/src/storage/default_storage_io.dart' as io;
import 'package:at_client/src/storage/default_storage_web.dart' as web;
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

void main() {
  group('web branch', () {
    test('defaultAtClientStorage throws a StateError naming storage:', () {
      expect(
          () => web.defaultAtClientStorage(
              atSign: '@web', storagePath: '/x', closedByClient: true),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('storage:'))));
    });

    test('defaultSyncQueueStore throws a StateError naming storage:', () {
      expect(
          () => web.defaultSyncQueueStore(atSign: '@web', storagePath: '/x'),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('storage:'))));
    });

    test('defaultStorageLocation is null', () {
      expect(web.defaultStorageLocation(atSign: '@web', storagePath: '/x'),
          isNull);
    });

    test('isDefaultStorage is false for every storage', () {
      expect(web.isDefaultStorage(InMemoryAtClientStorage(atSign: '@web')),
          isFalse);
      expect(
          web.isDefaultStorage(
              HiveAtClientStorage(atSign: '@web', storagePath: '/x')),
          isFalse);
    });
  });

  group('io branch', () {
    test('defaultAtClientStorage is a HiveAtClientStorage on the path', () {
      final storage = io.defaultAtClientStorage(
          atSign: '@io', storagePath: '/x', closedByClient: true);
      expect(storage, isA<HiveAtClientStorage>());
      expect((storage as HiveAtClientStorage).storagePath, '/x');
      expect(storage.closedByClient, isTrue);
    });

    test('defaultStorageLocation is the Hive location', () {
      expect(io.defaultStorageLocation(atSign: '@io', storagePath: '/x'),
          HiveAtClientStorage(atSign: '@io', storagePath: '/x').location);
    });

    test('isDefaultStorage is true only for Hive', () {
      expect(
          io.isDefaultStorage(
              HiveAtClientStorage(atSign: '@io', storagePath: '/x')),
          isTrue);
      expect(
          io.isDefaultStorage(InMemoryAtClientStorage(atSign: '@io')), isFalse);
    });

    test('defaultSyncQueueStore persists across reopen on one path', () async {
      final dir = Directory.systemTemp.createTempSync('default_queue_store_');
      final first =
          await io.defaultSyncQueueStore(atSign: '@io', storagePath: dir.path);
      await first.put('k', 'v');
      await first.close();
      final second =
          await io.defaultSyncQueueStore(atSign: '@io', storagePath: dir.path);
      expect(second.get('k'), 'v');
      await second.close();
      dir.deleteSync(recursive: true);
    });
  });

  group('persistenceBundle', () {
    test('null for backends with no Hive bundle', () {
      expect(
          RemoteOnlyAtClientStorage(
                  atSign: '@pb', remoteSecondary: MockRemoteSecondary())
              .persistenceBundle,
          isNull);
      expect(InMemoryAtClientStorage(atSign: '@pb').persistenceBundle, isNull);
    });

    test('Hive: null before attach, the client\'s bundle after', () async {
      final dir = Directory.systemTemp.createTempSync('default_bundle_');
      final pref = AtClientPreference()
        ..hiveStoragePath = dir.path
        ..commitLogPath = '${dir.path}/commit';
      expect(
          HiveAtClientStorage(atSign: '@pb', storagePath: dir.path)
              .persistenceBundle,
          isNull);

      final client =
          await AtClientImpl.create('@pb', 'wavi', pref) as AtClientImpl;
      expect(client.storage!.persistenceBundle, isNotNull);
      expect(client.persistenceBundle, same(client.storage!.persistenceBundle));

      await client.storage!.close();
      AtClientImpl.atClientInstanceMap.remove('@pb');
      dir.deleteSync(recursive: true);
    });
  });
}
