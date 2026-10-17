// Browser entrypoint for the crash lab (E2): the compiled file is both the page
// and, for SimpleOPFS, its dedicated-worker script. Config arrives as query
// parameters (`mode`, `vfs`, `db`); progress and the verdict go to the
// Playwright harness through `lab_ack` / `lab_result`.
//
//   mode=write   commit transactions until the harness kills the renderer
//   mode=verify  open the (possibly torn) database and report its invariant
//   flush=1      (write mode, IndexedDB) await the VFS flush before each ack
// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../lib/vfs_lab.dart';

typedef _Report = void Function(String kind, String payload);

Future<void> main() async {
  if (isDedicatedWorker) {
    final scope = globalContext as web.DedicatedWorkerGlobalScope;
    scope.onmessage = (web.MessageEvent e) {
      unawaited(_run((e.data as JSString).toDart,
          (kind, payload) => scope.postMessage('$kind:$payload'.toJS)));
    }.toJS;
    return;
  }

  void toHarness(String kind, String payload) =>
      globalContext.callMethod('lab_$kind'.toJS, payload.toJS);
  final cfg = jsonEncode(Uri.base.queryParameters);

  // SimpleOPFS only exists in a dedicated worker; IndexedDB stays on the main
  // thread, which is where D-19 runs Dart.
  if (Uri.base.queryParameters['vfs'] == LabVfs.simpleOpfs.name) {
    final worker = web.Worker('e2.dart.js'.toJS);
    worker.onmessage = (web.MessageEvent e) {
      final msg = (e.data as JSString).toDart;
      final split = msg.indexOf(':');
      toHarness(msg.substring(0, split), msg.substring(split + 1));
    }.toJS;
    worker.postMessage(cfg.toJS);
  } else {
    await _run(cfg, toHarness);
  }
}

Future<void> _run(String cfgJson, _Report report) async {
  final cfg = (jsonDecode(cfgJson) as Map).cast<String, String>();
  try {
    final db = await openLabDb(
        vfs: LabVfs.values.byName(cfg['vfs']!), name: cfg['db']!);
    applySchema(db);

    if (cfg['mode'] == 'write') {
      // Yield between transactions, as the real async server does, so the
      // VFS's asynchronous flush gets a chance to run. Never returns.
      for (var i = 1;; i++) {
        await writeTx(db, i);
        // `flush=1`: acknowledge only once the VFS has persisted the commit.
        if (cfg['flush'] == '1') await flushLabDb(db);
        report('ack', '$i');
        await Future<void>.delayed(Duration.zero);
      }
    }

    final check = checkInvariant(db);
    db.dispose();
    report(
        'result',
        jsonEncode({
          'opened': true,
          'integrityOk': check.integrityOk,
          'counterOk': check.counterOk,
          'maxCommit': check.maxCommit,
          'torn': check.torn,
        }));
  } catch (e) {
    report('result', jsonEncode({'opened': false, 'error': '$e'}));
  }
}
