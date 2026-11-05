/// Builds and checks the SDK map in `docs/map`.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:at_map/at_map.dart';
import 'package:path/path.dart' as p;

const _usage = '''
Builds and checks the SDK map in docs/map.

  dart run at_map build                write core.js and every flow's files
  dart run at_map build --indexes      write indexes.js alone
  dart run at_map check                the map job's gate
  dart run at_map check --server DIR   what a move to DIR's at_server would change
  dart run at_map bless FLOW.STEP...   record a step's body as reviewed
  dart run at_map diff-prod            steps that differ at the production tag

  --server-repo DIR   an at_server checkout at the pinned SHA, clean, with
                      dart pub get run in its server package; defaults to
                      AT_MAP_SERVER_REPO, then ../at_server beside this checkout
  --data DIR          where generated files are written and compared
''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('indexes', negatable: false)
    ..addOption('server')
    ..addOption('server-repo')
    ..addOption('data')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults a;
  try {
    a = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    exit(64);
  }
  if (a['help'] as bool || a.rest.isEmpty) {
    stdout.write(_usage);
    exit(a.rest.isEmpty && !(a['help'] as bool) ? 64 : 0);
  }
  final sdk = _workspaceRoot();
  final env = Platform.environment;
  final repo = a['server-repo'] as String? ??
      env['AT_MAP_SERVER_REPO'] ??
      p.join(p.dirname(sdk), 'at_server');
  final drift = a['server'] as String?;
  final data = a['data'] as String? ?? p.join(sdk, dataDir);
  final ws = Workspace(sdkDir: sdk, serverDir: drift ?? repo);
  void log(String line) => stdout.writeln(line);
  final int code;
  switch (a.rest.first) {
    case 'build':
      code = a['indexes'] as bool
          ? await runIndexes(ws, data: data, log: log)
          : await runBuild(ws, data: data, log: log);
    case 'check':
      code = drift == null
          ? await runCheck(ws, data: data, log: log)
          : await runDrift(ws, data: data, env: env, log: log);
    case 'bless':
      code = runBless(ws, a.rest.sublist(1), log: log);
    case 'diff-prod':
      code = await runDiffProd(ws, env: env, log: log);
    default:
      stderr.writeln('unknown command ${a.rest.first}\n\n$_usage');
      code = 64;
  }
  exit(code);
}

/// The at_client_sdk checkout: the pub workspace root above this package.
String _workspaceRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('\nworkspace:')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('at_map runs inside the at_client_sdk workspace');
      exit(64);
    }
    dir = parent;
  }
}
