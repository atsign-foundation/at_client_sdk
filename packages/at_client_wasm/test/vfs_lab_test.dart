// ignore_for_file: avoid_relative_lib_imports
// To make sqlite3.wasm reachable by the test page, download it the same way measure.sh does:
// curl -fsSL -o build/payload/sqlite3.wasm https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm

import 'package:test/test.dart';

import '../tool/vfs_lab/lib/vfs_lab.dart';

void main() {
  group('VFS Lab Core', () {
    test('schema applies and integrity_check == ok on IndexedDB VFS', () async {
      final db =
          await openLabDb(vfs: LabVfs.indexedDb, name: 'test_vfs_schema');
      addTearDown(db.dispose);

      applySchema(db);

      final check = checkInvariant(db);
      expect(check.integrityOk, isTrue);
      expect(check.torn, isEmpty);
    });

    test('writeTx x50 then checkInvariant -> torn empty', () async {
      final db = await openLabDb(vfs: LabVfs.indexedDb, name: 'test_vfs_tx50');
      addTearDown(db.dispose);

      applySchema(db);

      for (var i = 1; i <= 50; i++) {
        await writeTx(db, i);
      }

      final check = checkInvariant(db);
      expect(check.integrityOk, isTrue);
      expect(check.torn, isEmpty);
    });

    test('checkInvariant reports the highest committed id', () async {
      final db =
          await openLabDb(vfs: LabVfs.indexedDb, name: 'test_vfs_maxcommit');
      addTearDown(db.dispose);

      applySchema(db);
      expect(checkInvariant(db).maxCommit, 0);
      for (var i = 1; i <= 5; i++) {
        await writeTx(db, i);
      }

      expect(checkInvariant(db).maxCommit, 5);
    });

    test('writeTx keeps counters.last_commit_id equal to the highest commit',
        () async {
      final db =
          await openLabDb(vfs: LabVfs.indexedDb, name: 'test_vfs_counter');
      addTearDown(db.dispose);

      applySchema(db);
      for (var i = 1; i <= 10; i++) {
        await writeTx(db, i);
      }

      expect(checkInvariant(db).counterOk, isTrue);
    });

    test('control: a counter bump with no rows reports counterOk == false',
        () async {
      final db =
          await openLabDb(vfs: LabVfs.indexedDb, name: 'test_vfs_counter_torn');
      addTearDown(db.dispose);

      applySchema(db);
      db.execute(
          "UPDATE counters SET value = 9 WHERE name = 'last_commit_id';");

      final check = checkInvariant(db);
      expect(check.counterOk, isFalse);
      expect(check.torn, isEmpty);
    });

    test('deliberately broken control reports torn == [7]', () async {
      final db =
          await openLabDb(vfs: LabVfs.indexedDb, name: 'test_vfs_broken');
      addTearDown(db.dispose);

      applySchema(db);

      // Insert only the keystore half of tx 7
      db.execute(
        'INSERT INTO at_data (atkey, value, metadata) VALUES (?, ?, ?);',
        ['key_7', 'val_7', '{}'],
      );

      final check = checkInvariant(db);
      expect(check.torn, equals([7]));
    });

    test('openLabDb(simpleOpfs) outside a worker throws StateError', () async {
      expect(
        () => openLabDb(vfs: LabVfs.simpleOpfs, name: 'test_vfs_opfs'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'simpleOpfs requires a dedicated worker',
          ),
        ),
      );
    });
  });
}
