// Browser entrypoint for E4: open latency and database size versus key count.
// Query params: `vfs`, `db`, `n`, `phase` (populate | open). Like e2.dart, the
// compiled file is both the page and (for SimpleOPFS) its worker.
// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../lib/vfs_lab.dart';

typedef _Report = void Function(String payload);

Future<void> main() async {
  if (isDedicatedWorker) {
    final scope = globalContext as web.DedicatedWorkerGlobalScope;
    scope.onmessage = (web.MessageEvent e) {
      unawaited(
          _run((e.data as JSString).toDart, (p) => scope.postMessage(p.toJS)));
    }.toJS;
    return;
  }

  void toHarness(String p) =>
      globalContext.callMethod('lab_result'.toJS, p.toJS);
  final cfg = jsonEncode(Uri.base.queryParameters);
  if (Uri.base.queryParameters['vfs'] == LabVfs.simpleOpfs.name) {
    final worker = web.Worker('e4.dart.js'.toJS);
    worker.onmessage = (web.MessageEvent e) {
      toHarness((e.data as JSString).toDart);
    }.toJS;
    worker.postMessage(cfg.toJS);
  } else {
    await _run(cfg, toHarness);
  }
}

Future<void> _run(String cfgJson, _Report report) async {
  final cfg = (jsonDecode(cfgJson) as Map).cast<String, String>();
  final n = int.parse(cfg['n']!);
  final sw = Stopwatch()..start();
  int lap() {
    final ms = sw.elapsedMilliseconds;
    sw.reset();
    return ms;
  }

  try {
    final db = await openLabDb(
        vfs: LabVfs.values.byName(cfg['vfs']!), name: cfg['db']!);
    final openMs = lap();
    applySchema(db);
    final schemaMs = lap();

    if (cfg['phase'] == 'populate') {
      // ~200 B values, a single bulk transaction (the initial import shape).
      final value = 'v' * 200;
      db.execute('BEGIN;');
      final data = db.prepare(
          'INSERT INTO at_data (atkey, value, metadata) VALUES (?, ?, ?);');
      final log = db.prepare(
          'INSERT INTO commit_log (atkey, commit_id, operation, op_time) VALUES (?, ?, ?, ?);');
      for (var i = 1; i <= n; i++) {
        data.execute(['key_$i', value, '{}']);
        log.execute(['key_$i', i, '+', i]);
      }
      data.dispose();
      log.dispose();
      db.execute(
          "UPDATE counters SET value = $n WHERE name = 'last_commit_id';");
      db.execute('COMMIT;');
      final populateMs = lap();
      db.dispose();
      await flushLabDb(db);
      report(jsonEncode({
        'openMs': openMs,
        'populateMs': populateMs,
        'flushMs': lap(),
      }));
      return;
    }

    final count = db.select('SELECT count(*) FROM at_data;').first.values.first;
    final countMs = lap();
    db.select('SELECT value FROM at_data WHERE atkey = ?;', ['key_${n ~/ 2}']);
    final pointMs = lap();
    final pages = db.select('PRAGMA page_count;').first.values.first as int;
    final pageSize = db.select('PRAGMA page_size;').first.values.first as int;
    db.dispose();
    report(jsonEncode({
      'openMs': openMs,
      'schemaMs': schemaMs,
      'countMs': countMs,
      'pointMs': pointMs,
      'rows': count,
      'dbBytes': pages * pageSize,
    }));
  } catch (e) {
    report(jsonEncode({'error': '$e'}));
  }
}
