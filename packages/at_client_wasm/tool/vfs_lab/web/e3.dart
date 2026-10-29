// Browser entrypoint for E3: can SimpleOPFS host several databases, i.e. one per
// (atSign, enrollmentId)? The page spawns this same script as a worker; the
// worker runs a scenario (`scenario` query param) and posts a JSON verdict.
//
//   same-worker  two directories, two vfsNames, one worker
//   same-dir     the same directory opened twice in one worker
//   one-worker   (page-level) two workers, one directory each
// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../lib/vfs_lab.dart';

Future<void> main() async {
  if (isDedicatedWorker) {
    final scope = globalContext as web.DedicatedWorkerGlobalScope;
    scope.onmessage = (web.MessageEvent e) {
      unawaited(_scenario((e.data as JSString).toDart)
          .then((r) => scope.postMessage(jsonEncode(r).toJS)));
    }.toJS;
    return;
  }

  final q = Uri.base.queryParameters;
  final run = q['run']!;
  final scenarios = run == 'one-worker'
      ? [('dir-a-${q['id']}', 'single'), ('dir-b-${q['id']}', 'single')]
      : [(run, run)];
  final results = await Future.wait([
    for (final (tag, scenario) in scenarios)
      () {
        final done = Completer<String>();
        final w = web.Worker('e3.dart.js'.toJS);
        w.onmessage = (web.MessageEvent e) {
          done.complete((e.data as JSString).toDart);
        }.toJS;
        w.postMessage(
            jsonEncode({'scenario': scenario, 'id': q['id'], 'tag': tag}).toJS);
        return done.future;
      }(),
  ]);
  globalContext.callMethod(
      'lab_result'.toJS, jsonEncode(results.map(jsonDecode).toList()).toJS);
}

Future<Map<String, Object?>> _scenario(String cfgJson) async {
  final cfg = (jsonDecode(cfgJson) as Map).cast<String, String>();
  final id = cfg['id']!;
  try {
    switch (cfg['scenario']) {
      case 'same-worker':
        final a = await openLabDb(
            vfs: LabVfs.simpleOpfs,
            name: 'atsign-a-$id/enr1',
            vfsName: 'opfs-a-$id');
        final b = await openLabDb(
            vfs: LabVfs.simpleOpfs,
            name: 'atsign-b-$id/enr1',
            vfsName: 'opfs-b-$id');
        applySchema(a);
        applySchema(b);
        for (var i = 1; i <= 5; i++) {
          await writeTx(a, i);
        }
        for (var i = 1; i <= 3; i++) {
          await writeTx(b, i);
        }
        final (ca, cb) = (checkInvariant(a), checkInvariant(b));
        return {
          'scenario': 'same-worker',
          'opened': true,
          'aMax': ca.maxCommit,
          'bMax': cb.maxCommit,
          'isolated': ca.maxCommit == 5 &&
              cb.maxCommit == 3 &&
              ca.integrityOk &&
              cb.integrityOk,
        };
      case 'same-dir':
        final a = await openLabDb(
            vfs: LabVfs.simpleOpfs,
            name: 'shared-$id',
            vfsName: 'opfs-one-$id');
        applySchema(a);
        try {
          await openLabDb(
              vfs: LabVfs.simpleOpfs,
              name: 'shared-$id',
              vfsName: 'opfs-two-$id');
          return {'scenario': 'same-dir', 'secondOpenFailed': false};
        } catch (e) {
          return {
            'scenario': 'same-dir',
            'secondOpenFailed': true,
            'error': '$e'
          };
        }
      default: // 'single' — one db in a worker of its own
        final db = await openLabDb(
            vfs: LabVfs.simpleOpfs,
            name: '${cfg['tag']}',
            vfsName: 'opfs-${cfg['tag']}');
        applySchema(db);
        for (var i = 1; i <= 5; i++) {
          await writeTx(db, i);
        }
        return {
          'scenario': 'single',
          'tag': cfg['tag'],
          'opened': true,
          'maxCommit': checkInvariant(db).maxCommit
        };
    }
  } catch (e) {
    return {'scenario': cfg['scenario'], 'opened': false, 'error': '$e'};
  }
}
