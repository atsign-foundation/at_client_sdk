import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'decls.dart';
import 'engine.dart';
import 'evidence.dart';
import 'model.dart';
import 'output.dart';
import 'source.dart';

/// Where generated files live, relative to the SDK checkout.
const String dataDir = 'docs/map/data';

/// Prints one line of a command's output.
typedef Log = void Function(String line);

/// Whether [env] says the command runs in CI.
bool inCi(Map<String, String> env) => (env['CI'] ?? '').isNotEmpty;

Model? _model(Workspace ws, Log log) {
  final loaded = loadModel(ws.sdk);
  for (final f in loaded.failures) {
    log('FAIL $f');
  }
  return loaded.model;
}

String _seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

/// `at_map build`: writes core.js and every flow's files to [data], or
/// nothing when anything fails.
Future<int> runBuild(Workspace ws,
    {required String data,
    Budgets budgets = const Budgets(),
    required Log log}) async {
  final model = _model(ws, log);
  if (model == null) return 1;
  final problem = serverCheckoutProblem(ws.server.dir, model.roots.serverSha);
  if (problem != null) {
    log('FAIL $problem');
    return 1;
  }
  final b = await build(ws, model, budgets: budgets);
  log('tier 1 (parse-only) ${_seconds(b.tier1)} s; '
      'tier 2 (resolved) ${_seconds(b.tier2)} s');
  if (b.failures.isNotEmpty) {
    for (final f in b.failures) {
      log('FAIL $f');
    }
    log('build failed; nothing written');
    return 1;
  }
  final flowsDir = Directory(p.join(data, 'flows'));
  final stale = <String>[
    if (flowsDir.existsSync())
      for (final f in flowsDir.listSync().whereType<File>())
        if (!b.files.containsKey('flows/${p.basename(f.path)}'))
          'flows/${p.basename(f.path)}'
  ];
  writeAtomically(data, b.files, stale: stale);
  log('wrote ${b.files.length} files to $data');
  return 0;
}

/// `at_map check`: the map job's gate.
Future<int> runCheck(Workspace ws,
    {required String data,
    Budgets budgets = const Budgets(),
    required Log log}) async {
  final model = _model(ws, log);
  if (model == null) return 1;
  final roots = model.roots;
  final failures = <String>[];
  final problem = serverCheckoutProblem(ws.server.dir, roots.serverSha);
  if (problem != null) {
    log('FAIL $problem');
    return 1;
  }
  final tag = git(ws.serverGit, [
    'rev-parse',
    '--verify',
    '--quiet',
    'refs/tags/${roots.productionTag}^{commit}'
  ])?.trim();
  if (tag != roots.productionSha) {
    failures.add('production tag ${roots.productionTag} is pinned at '
        '${roots.productionSha} but resolves to ${tag ?? 'nothing'}');
  }

  final b = await build(ws, model, budgets: budgets);
  log('tier 1 (parse-only) ${_seconds(b.tier1)} s; '
      'tier 2 (resolved) ${_seconds(b.tier2)} s');
  failures.addAll(b.failures);

  if (b.failures.isEmpty) {
    for (final e in b.files.entries) {
      final f = File(p.join(data, e.key));
      final committed = f.existsSync() ? f.readAsStringSync() : null;
      if (committed != e.value) {
        failures.add('docs/map/data/${e.key} is not what a build produces; '
            'run dart run at_map build and commit the result');
      }
    }
    final flowsDir = Directory(p.join(data, 'flows'));
    if (flowsDir.existsSync()) {
      for (final f in flowsDir.listSync().whereType<File>()) {
        final rel = 'flows/${p.basename(f.path)}';
        if (!b.files.containsKey(rel)) {
          failures.add('docs/map/data/$rel is not what a build produces; '
              'no flow writes it');
        }
      }
    }
  }

  for (final s in b.steps) {
    if (s.hash == null || !s.changed) continue;
    if (s.lane.role == 'server') {
      failures.add('${s.id}: ${s.step.anchor.symbol} has changed since it '
          'was reviewed; read the step, then run '
          'dart run at_map bless ${s.id}');
    } else {
      log('REPORT ${s.id}: changed since reviewed (drawn amber)');
    }
  }
  final unverified = b.steps.fold<int>(0, (n, s) => n + s.unverified);
  log('REPORT $unverified unverified contract '
      '${unverified == 1 ? 'line' : 'lines'}');
  _reportEvidence(ws, model, b, log);

  for (final f in failures) {
    log('FAIL $f');
  }
  log(failures.isEmpty ? 'map check passed' : 'map check failed');
  return failures.isEmpty ? 0 : 1;
}

void _reportEvidence(Workspace ws, Model model, Build b, Log log) {
  final literals = testLiterals(ws.server);
  for (final f in model.flows) {
    final named = <String>[];
    for (final s in b.steps.where((s) => s.flow == f)) {
      for (var i = 0; i < s.exits.length; i++) {
        if (evidenceFor(s.exits[i].fixedText, literals).status == 'named') {
          named.add('${s.step.id}: ${s.exitIds[i]}');
        }
      }
    }
    final recorded = model.ratchet[f.id] ?? const [];
    final lost = recorded.where((e) => !named.contains(e)).toList();
    log('REPORT test evidence for ${f.id}: ${named.length} exits named by a '
        'test (text match); recorded ${recorded.length}'
        '${lost.isEmpty ? '' : '; no longer named: ${lost.join('; ')}'}');
  }
}

/// `at_map check --server DIR`: what a move to that checkout would change,
/// as counts in CI and as steps outside it.
Future<int> runDrift(Workspace ws,
    {required String data,
    required Map<String, String> env,
    required Log log}) async {
  final model = _model(ws, log);
  if (model == null) return 1;
  final problem = serverCheckoutProblem(ws.server.dir, model.roots.serverSha,
      pinned: false);
  if (problem != null) {
    log('FAIL $problem');
    return 1;
  }
  final b = await build(ws, model, pinned: false);
  final changed = <String, List<String>>{};
  final counts = {'anchors': 0, 'edges': 0, 'samples': 0, 'exits': 0};
  for (final f in model.flows) {
    final committed = _readFlow(p.join(data, 'flows/${f.id}.js'));
    final before = {
      for (final s in (committed?['steps'] as List? ?? const []).cast<Map>())
        s['id'] as String: _facts(s)
    };
    for (final s in b.steps.where((s) => s.flow == f)) {
      final now = _facts(s.json);
      final was = before[s.step.id] ?? const {};
      final what = [
        for (final k in counts.keys)
          if (now[k] != was[k]) k
      ];
      if (what.isEmpty) continue;
      changed[s.id] = what;
      for (final k in what) {
        counts[k] = counts[k]! + 1;
      }
    }
  }
  log('drift: ${changed.length} of ${b.steps.length} steps would change '
      '(anchors ${counts['anchors']}, edges ${counts['edges']}, samples '
      '${counts['samples']}, exits ${counts['exits']})');
  if (!inCi(env)) {
    for (final e in changed.entries) {
      log('  ${e.key}: ${e.value.join(', ')}');
    }
  }
  return 0;
}

Map<String, Object?>? _readFlow(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  final text = f.readAsStringSync();
  final i = text.indexOf('] = ');
  if (i < 0) return null;
  final json = text.substring(i + 4).trim();
  return jsonDecode(json.substring(0, json.length - 1)) as Map<String, Object?>;
}

Map<String, String> _facts(Map s) {
  final r = s['reached'] as Map?;
  final ex = s['exits'] as Map?;
  return {
    'anchors': '${s['hash']}',
    'edges': '${r?['text']}',
    'samples': jsonEncode(r?['replay']),
    'exits': jsonEncode([
      for (final e in (ex?['list'] as List? ?? const []).cast<Map>())
        [e['kind'], e['guard'], e['branch']]
    ]),
  };
}

/// `at_map diff-prod`: lists server steps absent or different at the
/// production tag, outside CI only.
Future<int> runDiffProd(Workspace ws,
    {required Map<String, String> env, required Log log}) async {
  if (inCi(env)) {
    log('diff-prod does not run in CI, whose logs are public');
    return 2;
  }
  final model = _model(ws, log);
  if (model == null) return 1;
  final roots = model.roots;
  final problem = serverCheckoutProblem(ws.server.dir, roots.serverSha);
  if (problem != null) {
    log('FAIL $problem');
    return 1;
  }
  final prod = GitRefTree(ws.serverGit, roots.productionSha);
  for (final f in model.flows) {
    for (final s in f.steps) {
      if (model.lanes[s.lane]!.role != 'server') continue;
      final now = _hashAt(ws.server.read(s.anchor.path), s.anchor);
      final then = _hashAt(prod.read(s.anchor.path), s.anchor);
      final id = '${f.id}.${s.id}';
      if (then == null) {
        log('$id: absent at ${roots.productionTag} '
            '(${s.anchor.symbol} not found)');
      } else if (then != now) {
        log('$id: differs at ${roots.productionTag}');
      }
    }
  }
  return 0;
}

String? _hashAt(String? text, CodeRef a) => text == null
    ? null
    : locateAnchor(indexDeclarations(parseUnit(text)), a).hash;

/// `at_map bless FLOW.STEP...`: records each step's current body hash as
/// reviewed, writing each flow file through [write].
int runBless(Workspace ws, List<String> ids,
    {required Log log, void Function(String path, String text)? write}) {
  write ??= (path, text) => File(ws.sdk.absolute(path)).writeAsStringSync(text);
  final model = _model(ws, log);
  if (model == null) return 1;
  final serverSteps = ids.any((id) => model.flows.any((f) => f.steps.any((s) =>
      '${f.id}.${s.id}' == id && model.lanes[s.lane]?.role == 'server')));
  final problem = serverSteps
      ? serverCheckoutProblem(ws.server.dir, model.roots.serverSha)
      : null;
  if (problem != null) {
    log('FAIL $problem');
    return 1;
  }
  var code = 0;
  for (final id in ids) {
    final dot = id.indexOf('.');
    final flow = dot < 0
        ? null
        : model.flows.where((f) => f.id == id.substring(0, dot)).firstOrNull;
    final step =
        flow?.steps.where((s) => s.id == id.substring(dot + 1)).firstOrNull;
    if (flow == null || step == null) {
      log('FAIL no step $id');
      code = 1;
      continue;
    }
    final tree = step.anchor.root == 'server' ? ws.server : ws.sdk;
    final hash = _hashAt(tree.read(step.anchor.path), step.anchor);
    if (hash == null) {
      log('FAIL $id: its anchor does not resolve, so there is nothing to bless');
      code = 1;
      continue;
    }
    final text = setReviewed(ws.sdk.read(flow.file)!, step.id, hash);
    if (text == null) {
      log('FAIL $id: cannot find the step in ${flow.file}');
      code = 1;
      continue;
    }
    write(flow.file, text);
    log('blessed $id at $hash');
  }
  return code;
}

/// [yaml] with step [id]'s `reviewed:` set to [hash], or null when the step
/// is not found.
String? setReviewed(String yaml, String id, String hash) {
  final lines = yaml.split('\n');
  final head = RegExp('^(\\s*)- id: ${RegExp.escape(id)}\\s*\$');
  final at = lines.indexWhere(head.hasMatch);
  if (at < 0) return null;
  final indent = head.firstMatch(lines[at])!.group(1)!.length + 2;
  var end = at + 1;
  while (end < lines.length) {
    final l = lines[end];
    if (l.trim().isNotEmpty && l.length - l.trimLeft().length < indent) {
      break;
    }
    end++;
  }
  final key = RegExp('^ {$indent}reviewed:');
  final line = '${' ' * indent}reviewed: $hash';
  final existing = lines.indexWhere(key.hasMatch, at);
  if (existing >= 0 && existing < end) {
    lines[existing] = line;
  } else {
    var insert = end;
    while (insert > at + 1 && lines[insert - 1].trim().isEmpty) {
      insert--;
    }
    lines.insert(insert, line);
  }
  return lines.join('\n');
}

/// `at_map build --indexes`: writes indexes.js alone.
Future<int> runIndexes(Workspace ws,
    {required String data, required Log log}) async {
  final model = _model(ws, log);
  if (model == null) return 1;
  final problem = serverCheckoutProblem(ws.server.dir, model.roots.serverSha);
  if (problem != null) {
    log('FAIL $problem');
    return 1;
  }
  final b = await build(ws, model);
  if (b.failures.isNotEmpty) {
    for (final f in b.failures) {
      log('FAIL $f');
    }
    return 1;
  }
  final literals = testLiterals(ws.server);
  Map<String, String> texts(Tree tree, bool Function(String) want) =>
      {for (final f in tree.files().where(want)) f: tree.read(f) ?? ''};
  final sdkTests = texts(
      ws.sdk,
      (f) =>
          f.endsWith('_test.dart') &&
          (f.startsWith('packages/') || f.startsWith('tests/')) &&
          f.contains('/test/'));
  final examples = texts(
      ws.sdk,
      (f) =>
          f.endsWith('.dart') &&
          (f.startsWith('packages/at_client/example/') ||
              f.startsWith('packages/at_client_flutter/example/')));
  final serverTests = texts(ws.server, isServerTest);
  final catalogue = RegExp(r'^///\s*Catalogue:\s*`?(features/\S+?\.feature)`?',
      multiLine: true);
  final sha = git(ws.sdk.dir, ['rev-parse', 'HEAD'])?.trim() ?? 'unknown';
  final flows = <String, Object?>{};
  final roots = model.roots;
  String serverUrl(String path, [int? line]) =>
      'https://github.com/${roots.serverGithub}/blob/${roots.serverSha}/'
      '$path${line == null ? '' : '#L$line'}';
  for (final f in model.flows) {
    final steps = <String, Object?>{};
    var named = 0;
    for (final s in b.steps.where((s) => s.flow == f)) {
      final member = s.step.anchor.symbol.split('.').last;
      final word = RegExp('\\b${RegExp.escape(member)}\\b');
      final server = s.lane.role == 'server';
      final tests = <Map<String, Object?>>[];
      final features = <String>{};
      for (final MapEntry(key: t, value: text)
          in (server ? serverTests : sdkTests).entries) {
        if (!word.hasMatch(text)) continue;
        tests.add({'path': t, 'url': server ? serverUrl(t) : '../../$t'});
        if (!server) {
          features.addAll(catalogue.allMatches(text).map((m) => m.group(1)!));
        }
      }
      final ex = <String>[
        if (!server)
          for (final e in examples.entries)
            if (word.hasMatch(e.value)) e.key
      ];
      final exits = <String, Object?>{};
      for (var i = 0; i < s.exits.length; i++) {
        final ev = evidenceFor(s.exits[i].fixedText, literals);
        if (ev.status == 'named') named++;
        exits[s.exitIds[i]] = {
          'status': ev.status,
          'tests': [
            for (final t in ev.tests)
              {
                'path': t.path,
                'test': t.test,
                'url': serverUrl(t.path, t.line),
              }
          ],
        };
      }
      steps[s.step.id] = {
        'mentionedBy': tests,
        'features': features.toList()..sort(),
        'examples': ex,
        'exits': exits,
      };
    }
    flows[f.id] = {'named': named, 'steps': steps};
  }
  final indexes = {
    'builtAt': sha,
    'server': roots.serverSha,
    'flows': flows,
  };
  writeAtomically(
      data, {'indexes.js': classicScript('MAP_INDEXES', null, indexes)});
  log('wrote indexes.js at $sha');
  return 0;
}
