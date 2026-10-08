import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import 'common.dart';

/// Lower bound for a SQLite-wasm backend: the remote-only app plus the
/// sqlite3 Dart bindings and an IndexedDB VFS. No AtClientStorage over
/// sqlite3/wasm exists yet, so the keystore adapter's own code is not counted.
Future<void> main() async {
  if (web.window.location.search.contains('run')) {
    final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
    sqlite3.registerVirtualFileSystem(
        await IndexedDbFileSystem.open(dbName: 'payload'),
        makeDefault: true);
    sqlite3.open('/db')
      ..execute('CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT)')
      ..execute('INSERT OR REPLACE INTO kv VALUES (?, ?)', ['k', 'v'])
      ..dispose();
  }
  final remote = RemoteSecondary('@payload', AtClientPreference());
  await exercise(
      RemoteOnlyAtClientStorage(atSign: '@payload', remoteSecondary: remote));
}
