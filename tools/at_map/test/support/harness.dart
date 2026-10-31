import 'dart:convert';
import 'dart:io';

import 'package:at_map/at_map.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The feature file every test here proves a scenario of.
const featureFile = 'features/at_map/sdk_map.feature';

/// The flow model the scenarios are about.
const flowYaml = 'docs/map/model/flows/share-record.yaml';

/// The at_client_sdk checkout holding this package.
String repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('\nworkspace:')) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) {
      throw StateError('no workspace root above ${Directory.current.path}');
    }
    dir = dir.parent;
  }
}

/// The at_server checkout at the pinned SHA, from AT_MAP_SERVER_REPO or
/// beside this checkout.
String serverRepo() {
  final env = Platform.environment['AT_MAP_SERVER_REPO'];
  final dir = env ?? p.join(p.dirname(repoRoot()), 'at_server');
  final pin = RegExp(r'sha: ([0-9a-f]{40})')
      .firstMatch(File(p.join(repoRoot(), 'docs/map/model/roots.yaml'))
          .readAsStringSync())!
      .group(1)!;
  final head = Process.runSync('git', ['-C', dir, 'rev-parse', 'HEAD']);
  if (head.exitCode != 0 || (head.stdout as String).trim() != pin) {
    fail('these tests read at_server at the pinned $pin: set '
        'AT_MAP_SERVER_REPO to a clean checkout of it with dart pub get run '
        'in packages/at_secondary_server (found $dir at '
        '${(head.stdout as String).trim()})');
  }
  return dir;
}

/// One run of a command: its exit code and output.
class Result {
  /// Creates a result.
  Result(this.code, this.lines, this.data);

  /// The exit code.
  final int code;

  /// What it printed.
  final List<String> lines;

  /// The data directory it read or wrote.
  final String data;

  /// Everything it printed.
  String get text => lines.join('\n');

  /// The lines starting FAIL.
  List<String> get failures =>
      lines.where((l) => l.startsWith('FAIL')).toList();

  /// A generated file's contents.
  String file(String rel) => File(p.join(data, rel)).readAsStringSync();

  @override
  String toString() => 'exit $code\n$text';
}

/// Runs the generator in-process over this checkout and the pinned
/// at_server, with files replaced in memory.
class Harness {
  Harness._(this.ws, this.temp);

  /// The workspace every run shares, so analysis is resolved once.
  final Workspace ws;

  /// Scratch space removed by [close].
  final Directory temp;

  /// Opens a harness.
  static Future<Harness> open() async {
    final temp = await Directory.systemTemp.createTemp('at_map_test');
    return Harness._(
        Workspace(sdkDir: repoRoot(), serverDir: serverRepo()), temp);
  }

  /// Removes scratch space.
  Future<void> close() => temp.delete(recursive: true);

  /// The committed data directory.
  String get committedData => p.join(repoRoot(), 'docs/map/data');

  /// A fresh, empty data directory.
  String freshData() {
    final d = Directory(p.join(temp.path, 'data${_n++}'))..createSync();
    return d.path;
  }

  int _n = 0;

  /// A file of this checkout as committed in the working tree.
  String sdkFile(String rel) =>
      File(p.join(repoRoot(), rel)).readAsStringSync();

  /// A file of the pinned at_server checkout.
  String serverFile(String rel) =>
      File(p.join(ws.server.dir, rel)).readAsStringSync();

  Future<void> _idle = Future<void>.value();

  /// Runs [body] once every earlier use of [ws] has finished.
  ///
  /// A test that times out leaves its build running, and the next test's
  /// overlays would change the files that build is still resolving; waiting
  /// for it keeps every build on one consistent analysis session.
  Future<T> exclusive<T>(Future<T> Function() body) {
    final turn = _idle.then((_) => body());
    _idle = turn.then((_) {}, onError: (Object _) {});
    return turn;
  }

  Future<Result> _run(Future<int> Function(Log log) body, String data,
      {Map<String, String> sdk = const {},
      Map<String, String> server = const {},
      Map<String, String> outside = const {},
      String? serverGit}) {
    return exclusive(() async {
      await ws.overlay(sdk: sdk, server: server, outside: outside);
      ws.serverGit = serverGit ?? ws.server.dir;
      final lines = <String>[];
      final code = await body(lines.add);
      return Result(code, lines, data);
    });
  }

  /// `at_map build` into [data], a fresh directory when null.
  Future<Result> build(
      {String? data,
      Map<String, String> sdk = const {},
      Map<String, String> server = const {},
      Map<String, String> outside = const {},
      String? serverGit,
      Budgets budgets = const Budgets()}) {
    final d = data ?? freshData();
    return _run((log) => runBuild(ws, data: d, budgets: budgets, log: log), d,
        sdk: sdk, server: server, outside: outside, serverGit: serverGit);
  }

  /// `at_map build --indexes` into [data].
  Future<Result> indexes(
      {required String data,
      Map<String, String> sdk = const {},
      Map<String, String> server = const {}}) {
    return _run((log) => runIndexes(ws, data: data, log: log), data,
        sdk: sdk, server: server);
  }

  /// `at_map check` against [data], the committed files when null.
  Future<Result> check(
      {String? data,
      Map<String, String> sdk = const {},
      Map<String, String> server = const {},
      Map<String, String> outside = const {},
      String? serverGit}) {
    final d = data ?? committedData;
    return _run((log) => runCheck(ws, data: d, log: log), d,
        sdk: sdk, server: server, outside: outside, serverGit: serverGit);
  }

  /// `at_map check --server` with [env] as the environment.
  Future<Result> drift(
      {required Map<String, String> env,
      String? data,
      Map<String, String> server = const {},
      String? serverGit}) {
    final d = data ?? committedData;
    return _run((log) => runDrift(ws, data: d, env: env, log: log), d,
        server: server, serverGit: serverGit);
  }

  /// `at_map diff-prod` with [env] as the environment.
  Future<Result> diffProd({required Map<String, String> env}) {
    return _run((log) => runDiffProd(ws, env: env, log: log), '');
  }

  /// A bare clone of the server repository sharing its objects, for moving
  /// tags without touching the checkout.
  String cloneServerGit() {
    final dir = p.join(temp.path, 'server${_n++}.git');
    final r = Process.runSync(
        'git', ['clone', '--quiet', '--bare', '--shared', ws.server.dir, dir]);
    if (r.exitCode != 0) fail('git clone failed: ${r.stderr}');
    return dir;
  }
}

/// Runs git in [dir], failing the test when it fails.
String gitIn(String dir, List<String> args) {
  final r = Process.runSync('git', ['-C', dir, ...args]);
  if (r.exitCode != 0) fail('git ${args.join(' ')} failed: ${r.stderr}');
  return (r.stdout as String).trim();
}

/// [text] with [from] replaced by [to], failing when [from] is absent, so a
/// fixture edit that no longer applies cannot pass silently.
String edit(String text, String from, String to) {
  if (!text.contains(from)) fail('fixture edit no longer applies: "$from"');
  return text.replaceFirst(from, to);
}

/// Every file under [dir], relative path to bytes.
Map<String, List<int>> snapshot(String dir) => {
      for (final f
          in Directory(dir).listSync(recursive: true).whereType<File>())
        p.relative(f.path, from: dir): f.readAsBytesSync()
    };

/// The flow file's JSON.
Map<String, Object?> flowJson(Result r) {
  final text = r.file('flows/share-record.js');
  final json = text.substring(text.indexOf('] = ') + 4).trim();
  return jsonDecode(json.substring(0, json.length - 1)) as Map<String, Object?>;
}

/// One step of a flow file.
Map<String, Object?> stepOf(Map<String, Object?> flow, String id) =>
    (flow['steps'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((s) => s['id'] == id);
