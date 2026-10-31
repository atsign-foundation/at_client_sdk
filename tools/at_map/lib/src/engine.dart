import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'analysis.dart';
import 'decls.dart';
import 'dispatch.dart';
import 'edges.dart';
import 'exits.dart';
import 'gherkin.dart';
import 'model.dart';
import 'output.dart';
import 'skeleton.dart';
import 'source.dart';
import 'tokens.dart';

/// The longest snippet kept whole; a longer declaration is cut to a window
/// around its anchored statement.
const int maxSnippetLines = 160;

/// The two checkouts a build reads, and the analysis over them.
class Workspace {
  /// Creates a workspace over the SDK checkout [sdkDir] and the at_server
  /// checkout [serverDir]; [serverGit] holds the server's tags and history
  /// when it is not [serverDir] itself.
  Workspace(
      {required String sdkDir, required String serverDir, String? serverGit})
      : sdk = Tree('sdk', sdkDir),
        server = Tree('server', serverDir, tracked: true),
        serverGit = serverGit ?? serverDir;

  /// This checkout of at_client_sdk.
  Tree sdk;

  /// The at_server checkout.
  Tree server;

  /// Where the server's tags and history are read.
  String serverGit;

  /// Files outside both checkouts replaced in memory, by absolute path.
  Map<String, String> outside = {};

  /// The roots of the model being built.
  Roots? roots;

  Resolver? _resolver;
  Dispatch? _dispatch;

  /// Replaces every overlay: [sdk] and [server] by relative path,
  /// [outside] by absolute path.
  Future<void> overlay(
      {Map<String, String> sdk = const {},
      Map<String, String> server = const {},
      Map<String, String> outside = const {}}) async {
    this.sdk = Tree('sdk', this.sdk.dir, overlays: Map.of(sdk));
    this.server = Tree('server', this.server.dir,
        overlays: Map.of(server), tracked: true);
    this.outside = Map.of(outside);
    _dispatch = null;
    await _resolver?.setOverlays(_absoluteOverlays());
  }

  Map<String, String> _absoluteOverlays() => {
        for (final e in sdk.overlays.entries) sdk.absolute(e.key): e.value,
        for (final e in server.overlays.entries)
          server.absolute(e.key): e.value,
        ...outside,
      };

  /// The resolver for [roots], created on first use.
  Future<Resolver> resolver(Roots roots) async {
    final r = _resolver;
    if (r != null &&
        r.serverPackage == roots.serverPackage &&
        _listEq(r.sdkPackages, _sdkPackages(roots))) {
      return r;
    }
    final fresh = Resolver(
        sdkDir: sdk.dir,
        serverDir: server.dir,
        sdkPackages: _sdkPackages(roots),
        serverPackage: roots.serverPackage);
    _resolver = fresh;
    _dispatch = null;
    await fresh.setOverlays(_absoluteOverlays());
    return fresh;
  }

  List<String> _sdkPackages(Roots roots) => [
        for (final l in roots.sdkLib) p.dirname(l),
        roots.sdkAtCommons,
      ];

  /// The server's dispatch table, read once per set of overlays.
  Future<Dispatch> dispatch(Roots roots) async =>
      _dispatch ??= await Dispatch.load(await resolver(roots));
}

bool _listEq(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

/// Why the at_server checkout cannot be built from, or null when it can.
String? serverCheckoutProblem(String dir, String sha, {bool pinned = true}) {
  final head = git(dir, ['rev-parse', 'HEAD'])?.trim();
  if (head == null) return 'at_server at $dir is not a git checkout';
  if (pinned && head != sha) {
    return 'at_server at $dir is at $head, not the pinned $sha; check the pin '
        'out in a clean clone and pass --server-repo';
  }
  final dirty =
      git(dir, ['status', '--porcelain', '--untracked-files=no'])?.trim();
  if (dirty == null || dirty.isNotEmpty) {
    return 'at_server at $dir has uncommitted changes; tier 2 reads its '
        'working tree';
  }
  return null;
}

/// What one step resolved to.
class StepOut {
  /// Creates a step record.
  StepOut(this.flow, this.step, this.lane);

  /// The flow.
  final Flow flow;

  /// The model step.
  final Step step;

  /// Its lane.
  final Lane lane;

  /// `<flow>.<step>`.
  String get id => '${flow.id}.${step.id}';

  /// Failures found for this step.
  final List<String> failures = [];

  /// The anchored declaration's body hash.
  String? hash;

  /// Whether the body differs from its reviewed hash.
  bool get changed => hash != null && hash != step.reviewed;

  /// The step's record in the flow file.
  Map<String, Object?> json = {};

  /// Facts compared by a drift check: anchors, edges, samples, exits.
  final Map<String, Object?> facts = {};

  /// Exits on the step's path, for test evidence.
  List<Exit> exits = const [];

  /// The ids [exits] carry in the flow file.
  List<String> exitIds = const [];

  /// Unbacked contract lines that are not authority claims.
  int unverified = 0;

  Decl? _decl;
  AstNode? _resolved;
}

/// A finished build, in memory.
class Build {
  /// Creates a build record.
  Build(this.model);

  /// The model built from.
  final Model model;

  /// Generated files, relative to the data directory.
  final Map<String, String> files = {};

  /// Everything that fails the build.
  final List<String> failures = [];

  /// Every step, in flow order.
  final List<StepOut> steps = [];

  /// The lane note.
  String laneNote = '';

  /// Time spent in parse-only work.
  Duration tier1 = Duration.zero;

  /// Time spent in resolved analysis.
  Duration tier2 = Duration.zero;
}

/// Builds every flow in [model] from [ws]; nothing is written.
Future<Build> build(Workspace ws, Model model,
    {Budgets budgets = const Budgets(), bool pinned = true}) async {
  final b = Build(model);
  final roots = model.roots;
  ws.roots = roots;
  final sw = Stopwatch()..start();

  if (pinned) {
    final behind = git(ws.serverGit,
        ['rev-list', '--count', '${roots.productionSha}..${roots.serverSha}']);
    final shallow =
        git(ws.serverGit, ['rev-parse', '--is-shallow-repository'])?.trim();
    if (behind == null || shallow != 'false') {
      b.failures.add('cannot count the commits from production '
          '${roots.productionTag} to the pin: at_server at ${ws.serverGit} '
          'needs its full history');
    } else {
      b.laneNote = 'Server lane at at_server ${roots.serverBranch} '
          '${roots.serverSha.substring(0, 9)}; production '
          '${roots.productionTag} is ${behind.trim()} commits behind.';
    }
  }

  for (final f in model.flows) {
    for (final s in f.steps) {
      b.steps.add(StepOut(f, s, model.lanes[s.lane]!));
    }
  }

  for (final s in b.steps) {
    _tier1(ws, s);
  }
  _validateLinks(ws, model, b);
  final storeOut = _stores(ws, model, b);
  b.tier1 = sw.elapsed;

  final resolver = await ws.resolver(roots);
  for (final s in b.steps) {
    await _resolve(ws, resolver, s);
  }
  for (final f in model.flows) {
    final steps = b.steps.where((s) => s.flow == f).toList();
    for (var i = 0; i < steps.length; i++) {
      await _transition(ws, resolver, model, steps, i);
    }
    for (final s in steps) {
      await _exitsAndContracts(ws, resolver, s);
    }
  }
  b.tier2 = sw.elapsed - b.tier1;

  for (final s in b.steps) {
    b.failures.addAll(s.failures);
  }
  _render(ws, model, b, storeOut, budgets);
  return b;
}

String _url(Roots roots, String root, String path, {int? from, int? to}) {
  if (root == 'sdk') return '../../$path';
  final lines = from == null
      ? ''
      : (to == null || to == from ? '#L$from' : '#L$from-L$to');
  return 'https://github.com/${roots.serverGithub}/blob/${roots.serverSha}/'
      '$path$lines';
}

void _tier1(Workspace ws, StepOut s) {
  final a = s.step.anchor;
  final tree = a.root == 'server' ? ws.server : ws.sdk;
  final String? text;
  try {
    text = tree.read(a.path);
  } on SourceError catch (e) {
    s.failures.add('${s.id}: $e');
    s.facts['anchor'] = 'FAIL';
    return;
  }
  if (text == null) {
    s.failures.add('${s.id}: anchor ${a.root}:${a.path} does not exist');
    s.facts['anchor'] = 'FAIL missing file';
    return;
  }
  final unit = parseUnit(text);
  final idx = indexDeclarations(unit);
  final hit = locateAnchor(idx, a);
  final decl = hit.decl;
  if (decl == null) {
    final cands = _candidates(idx, s.step, a.symbol);
    s.failures.add('${s.id}: anchor ${a.root}:${a.path} has '
        '${hit.declarations == 0 ? 'no declaration' : '${hit.declarations} declarations'} '
        '${a.symbol}'
        '${cands.isEmpty ? '' : '; candidates: ${cands.join(', ')}'}');
    s.facts['anchor'] = 'FAIL no declaration';
    return;
  }
  final li = unit.lineInfo;
  if (hit.hash == null) {
    s.failures.add('${s.id}: anchor ${a.symbol} holds "${a.contains}" '
        '${hit.matches} times, not exactly once (compared as tokens)');
    s.facts['anchor'] = 'FAIL contains ${hit.matches}';
    return;
  }
  final matchLine =
      hit.match == null ? null : li.getLocation(hit.match!).lineNumber;
  s.hash = hit.hash;
  s._decl = decl;
  s.facts['anchor'] = s.hash;

  final start = firstCodeToken(decl.node).offset;
  final first = li.getLocation(start).lineNumber;
  final last = li.getLocation(decl.node.end).lineNumber;
  final snippet = _snippet(text, li, first, last, matchLine);
  final server = a.root == 'server';
  s.json = {
    'id': s.step.id,
    'lane': s.step.lane,
    if (s.step.sublane != null) 'sublane': s.step.sublane,
    'intent': s.step.intent,
    'anchor': {
      'root': a.root,
      'path': a.path,
      'symbol': a.symbol,
      if (a.contains != null) 'contains': a.contains,
      'url': _url(ws.roots!, a.root, a.path,
          from: server ? first : null, to: server ? last : null),
      if (server) 'lines': [first, last],
      if (server && matchLine != null) 'match': matchLine,
    },
    'snippet': {
      'text': snippet.$1,
      if (server) 'startLine': snippet.$2,
      'cut': snippet.$3,
    },
    'skeleton': skeleton(decl.node),
    'hash': s.hash,
    'reviewed': s.step.reviewed,
    'changed': s.changed,
    'touches': s.step.touches,
    'links': [
      for (final l in s.step.links) {'title': l.title, 'href': l.href}
    ],
    if (s.step.navigateTo != null) 'navigateTo': s.step.navigateTo,
  };
}

/// Where an anchor lands in a file's declarations.
class AnchorHit {
  /// Creates a record.
  AnchorHit(this.declarations,
      {this.decl, this.matches = 0, this.match, this.hash});

  /// How many declarations carry the symbol.
  final int declarations;

  /// The one declaration, when there is exactly one.
  final Decl? decl;

  /// How many times `contains` occurs in it.
  final int matches;

  /// The offset of the one occurrence of `contains`.
  final int? match;

  /// The body hash, when the anchor resolves.
  final String? hash;
}

/// Resolves [a] against the declarations [idx] of its file: one declaration,
/// and its `contains` exactly once as tokens.
AnchorHit locateAnchor(Map<String, List<Decl>> idx, CodeRef a) {
  final hits = idx[a.symbol] ?? const [];
  if (hits.length != 1) return AnchorHit(hits.length);
  final decl = hits.single;
  final tokens = nodeTokens(decl.node);
  int? match;
  var matches = 0;
  if (a.contains != null) {
    final m = tokenMatches(tokens, lexemes(a.contains!));
    matches = m.length;
    if (m.length != 1) return AnchorHit(1, decl: decl, matches: m.length);
    match = m.single;
  }
  return AnchorHit(1,
      decl: decl,
      matches: matches,
      match: match,
      hash: tokenHash(tokens, skip: decl.nameToken));
}

(String, int, bool) _snippet(
    String text, LineInfo li, int first, int last, int? match) {
  final lines = text.split('\n');
  var from = first;
  var to = last;
  var cut = false;
  if (last - first + 1 > maxSnippetLines) {
    cut = true;
    final centre = match ?? first;
    from = (centre - maxSnippetLines ~/ 2).clamp(first, last);
    to = (from + maxSnippetLines - 1).clamp(first, last);
  }
  return (lines.sublist(from - 1, to).join('\n'), from, cut);
}

List<String> _candidates(
    Map<String, List<Decl>> idx, Step step, String symbol) {
  final out = <String>{};
  if (step.reviewed != null) {
    for (final e in idx.entries) {
      for (final d in e.value) {
        final h = tokenHash(nodeTokens(d.node), skip: d.nameToken);
        if (h == step.reviewed) out.add('${e.key} (same body as reviewed)');
      }
    }
  }
  final dot = symbol.indexOf('.');
  final prefix = dot < 0 ? '' : symbol.substring(0, dot + 1);
  final member = symbol.substring(dot + 1);
  for (final name in idx.keys) {
    if (!name.startsWith(prefix) ||
        name.substring(prefix.length).contains('.')) {
      continue;
    }
    final other = name.substring(prefix.length);
    if (_distance(other, member) <= (member.length / 4).ceil()) {
      out.add(name);
    }
  }
  return out.toList()..sort();
}

int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      cur.add([
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
      ].reduce((x, y) => x < y ? x : y));
    }
    prev = cur;
  }
  return prev[b.length];
}

void _validateLinks(Workspace ws, Model model, Build b) {
  final files = ws.sdk.files();
  bool exists(String path) =>
      ws.sdk.read(path) != null || files.any((f) => f.startsWith('$path/'));
  void check(String holder, Link l) {
    if (!allowedHref(l.href, existsInRepo: exists)) {
      b.failures.add('$holder: link "${l.href}" is neither a path in this '
          'repository nor under https://github.com/atsign-foundation/');
    }
  }

  for (final lens in model.lenses) {
    for (final l in lens.links) {
      check('lens ${lens.id}', l);
    }
  }
  for (final s in b.steps) {
    for (final l in s.step.links) {
      check(s.id, l);
    }
  }
}

List<Map<String, Object?>> _stores(Workspace ws, Model model, Build b) {
  final out = <Map<String, Object?>>[];
  for (final st in model.stores.values) {
    final a = st.anchor;
    final tree = a.root == 'server' ? ws.server : ws.sdk;
    final text = tree.read(a.path);
    final ok = text != null &&
        (indexDeclarations(parseUnit(text))[a.symbol]?.length ?? 0) == 1;
    if (!ok) {
      b.failures.add('store ${st.id}: ${a.root}:${a.path} has no single '
          'declaration ${a.symbol}');
    }
    out.add({
      'id': st.id,
      'title': st.title,
      'root': a.root,
      'symbol': a.symbol,
      'url': _url(model.roots, a.root, a.path),
    });
  }
  return out;
}

Future<void> _resolve(Workspace ws, Resolver r, StepOut s) async {
  if (s._decl == null) return;
  final a = s.step.anchor;
  final tree = a.root == 'server' ? ws.server : ws.sdk;
  s._resolved = await r.declaration(tree.absolute(a.path), a.symbol);
  if (s._resolved == null) {
    s.failures.add('${s.id}: ${a.symbol} does not resolve in '
        '${a.root}:${a.path}');
  }
}

Future<List<CommonsVersion>> _commons(Workspace ws, Resolver r) async {
  const uri = 'package:at_commons/src/verb/syntax.dart';
  final roots = ws.roots!;
  final lock = ws.server.read('${roots.serverPackage}/pubspec.lock');
  final serverVersion = (lock == null
      ? null
      : loadYaml(lock)['packages']?['at_commons']?['version']) as String?;
  final pub = ws.sdk.read('${roots.sdkAtCommons}/pubspec.yaml');
  final sdkVersion = (pub == null ? null : loadYaml(pub)['version']) as String?;
  Future<String?> Function(String) from(Future<dynamic> Function(String) lib) =>
      (field) async {
        final l = await lib(uri);
        final v = l?.getClass('VerbSyntax')?.getField(field);
        return v?.computeConstantValue()?.toStringValue() as String?;
      };
  return [
    CommonsVersion(
        serverVersion ?? '?', "at_server's lock", from(r.serverLibrary)),
    CommonsVersion(sdkVersion ?? '?', 'this checkout', from(r.sdkLibrary)),
  ];
}

Future<void> _transition(
    Workspace ws, Resolver r, Model model, List<StepOut> steps, int i) async {
  final s = steps[i];
  final rc = s.step.reached;
  final prev = rc.from == null
      ? (i == 0 ? null : steps[i - 1])
      : steps.firstWhere((x) => x.step.id == rc.from);
  final edge = prev == null ? '' : '${prev.id} -> ${s.id}';
  final reached = <String, Object?>{'kind': rc.kind};
  if (prev != null) reached['from'] = prev.step.id;
  s.json['reached'] = reached;
  final path = <AstNode>[];
  s.facts['path'] = path;

  void fail(String why) {
    s.failures.add('$edge: $why');
    s.facts['transition'] = 'FAIL $why';
  }

  if (rc.kind == 'entry') {
    reached['text'] = 'entry';
    s.facts['transition'] = 'entry';
    if (s._resolved != null) path.add(s._resolved!);
    return;
  }
  if (prev == null) return;
  if (s._resolved == null) {
    s.facts['transition'] = 'FAIL unresolved';
    return;
  }
  final prevDecl = prev._resolved;

  Future<bool> chain(AstNode from, List<String> via) async {
    var cur = from;
    var curName = _nameOf(from);
    for (final v in via) {
      final el = findCall(cur, v);
      if (el == null) {
        fail('$curName no longer calls $v');
        return false;
      }
      final d = await r.declarationOf(el);
      if (d == null) {
        fail('$v does not resolve to a declaration in either checkout');
        return false;
      }
      path.add(d);
      cur = d;
      curName = v;
    }
    if (findCall(cur, s.step.anchor.symbol) == null) {
      fail('$curName no longer calls ${s.step.anchor.symbol}');
      return false;
    }
    return true;
  }

  switch (rc.kind) {
    case 'untraced':
      reached['text'] = 'via (untraced): ${rc.note}';
      s.facts['transition'] = 'untraced';
    case 'push':
      reached['text'] = 'push: ${rc.note}';
      s.facts['transition'] = 'push';
    case 'declared':
      final t = rc.through!;
      final tree = t.root == 'server' ? ws.server : ws.sdk;
      final text = tree.read(t.path);
      final found = text != null &&
          (indexDeclarations(parseUnit(text))[t.symbol]?.length ?? 0) == 1;
      if (!found) {
        fail('declared hop through ${t.symbol}: no such declaration in '
            '${t.root}:${t.path}');
        return;
      }
      reached['text'] = 'declared hop through ${t.symbol}';
      reached['through'] = t.symbol;
      if (rc.note != null) reached['note'] = rc.note;
      s.facts['transition'] = 'declared ${t.symbol}';
    case 'wire':
      if (rc.nested) reached['nested'] = true;
      reached['verb'] = rc.verb;
      reached['sample'] = rc.sample;
      reached['via'] = rc.via;
      final d = await ws.dispatch(model.roots);
      final replays = await d.replay(rc.sample!, await _commons(ws, r));
      final first = rc.via.isEmpty ? s.step.anchor.symbol : rc.via.first;
      final want = first.split('.').first;
      reached['replay'] = [
        for (final rp in replays)
          {
            'commons': rp.commons.toString(),
            'handler': rp.handler,
            'syntax':
                rp.syntaxField == null ? null : 'VerbSyntax.${rp.syntaxField}',
            'parses': rp.parses,
          }
      ];
      s.facts['samples'] = [
        for (final rp in replays)
          '${rp.commons} ${rp.handler} ${rp.syntaxField} ${rp.parses} ${rp.error}'
      ];
      var ok = true;
      for (final rp in replays) {
        if (rp.error != null) {
          fail('sample "${rc.sample}": ${rp.error}');
          ok = false;
        } else if (rp.handler != want) {
          fail(
              'sample "${rc.sample}": dispatch chose ${rp.handler ?? 'no handler'}, '
              'not $want, with ${rp.commons}');
          ok = false;
        } else if (!rp.parses) {
          fail('sample "${rc.sample}" is rejected by '
              'VerbSyntax.${rp.syntaxField} in ${rp.commons}');
          ok = false;
        }
      }
      if (!ok) return;
      final handler = d.handlers.firstWhere((h) => h.name == want).element;
      if (rc.via.isEmpty) {
        reached['text'] =
            'wire ${_verbOf(rc.sample!)}${rc.nested ? ' (nested)' : ''}';
        s.facts['transition'] = 'wire $want';
        path.add(s._resolved!);
        return;
      }
      final m = handler.lookUpMethod(
          name: rc.via.first.split('.').last, library: handler.library);
      final md = m == null ? null : await r.declarationOf(m);
      if (md == null || qualifiedName(m!) != rc.via.first) {
        fail('${rc.via.first} is not declared by $want');
        return;
      }
      path.add(md);
      if (!await chain(md, rc.via.sublist(1))) return;
      reached['text'] = 'wire ${_verbOf(rc.sample!)}, via ${rc.via.join(', ')}';
      s.facts['transition'] = 'wire $want via ${rc.via.join(',')}';
      path.add(s._resolved!);
      return;
    case 'stream':
    case 'field':
      if (prevDecl == null) return;
      final t = rc.through!;
      final binders = Binders(r, t.root == 'server' ? ws.server : ws.sdk,
          t.root == 'server' ? model.roots.serverLib : model.roots.sdkLib);
      final field = await binders.field(t.path, t.symbol);
      final kind = rc.kind == 'stream' ? 'stream' : 'function-field';
      if (field == null) {
        fail('$kind hop through ${t.symbol}: the field is not declared in '
            '${t.root}:${t.path}');
        return;
      }
      final fed = rc.kind == 'stream'
          ? binders.streamsAddedTo(prevDecl)
          : binders.invokedFunctionFields(prevDecl);
      if (!fed.any((f) => f.baseElement == field.baseElement)) {
        fail('$kind hop through ${t.symbol}: ${prev.step.anchor.symbol} '
            '${rc.kind == 'stream' ? 'adds nothing to' : 'never invokes'} it');
        return;
      }
      final bindings = rc.kind == 'stream'
          ? await binders.streamBindings(field)
          : await binders.functionFieldBindings(field);
      final consumer = rc.via.isEmpty ? s.step.anchor.symbol : rc.via.first;
      final bound =
          bindings.where((b) => qualifiedName(b.consumer) == consumer).toList();
      if (bound.isEmpty) {
        fail('$kind hop through ${t.symbol}: nothing binds it to $consumer');
        return;
      }
      if (rc.via.isNotEmpty) {
        final cd = await r.declarationOf(bound.first.consumer);
        if (cd == null) {
          fail('$consumer does not resolve');
          return;
        }
        path.add(cd);
        if (!await chain(cd, rc.via.sublist(1))) return;
      }
      reached['text'] = '$kind hop through ${t.symbol}, bound in '
          '${bound.first.where}'
          '${rc.via.isEmpty ? '' : ', via ${rc.via.join(', ')}'}';
      reached['through'] = t.symbol;
      reached['via'] = rc.via;
      s.facts['transition'] = '$kind ${t.symbol} ${rc.via.join(',')}';
      path.add(s._resolved!);
      return;
    case 'via':
    case 'call':
      if (prevDecl == null) return;
      if (rc.kind == 'via') {
        if (!await chain(prevDecl, rc.via)) return;
        reached['text'] = 'via ${rc.via.join(', ')}';
        reached['via'] = rc.via;
        s.facts['transition'] = 'via ${rc.via.join(',')}';
        path.add(s._resolved!);
        return;
      }
      if (findCall(prevDecl, s.step.anchor.symbol) != null) {
        reached['text'] = 'call';
        s.facts['transition'] = 'call';
        path.add(s._resolved!);
        return;
      }
      if (rc.from != null) {
        fail('${prev.step.anchor.symbol} no longer calls '
            '${s.step.anchor.symbol}');
        return;
      }
      final binder = await _bindsTo(ws, r, model, prev, s);
      if (binder != null) {
        reached['kind'] = binder.$1;
        reached['text'] = binder.$2;
        s.facts['transition'] = binder.$2;
        path.add(s._resolved!);
        return;
      }
      s.failures.add('$edge: ${prev.step.anchor.symbol} does not call '
          '${s.step.anchor.symbol}, no via, hop, wire or push is declared, '
          'and no binder binds the two; neither an edge nor a hop');
      s.facts['transition'] = 'FAIL neither';
  }
  if (s._resolved != null && path.isEmpty) path.add(s._resolved!);
}

/// The verb a sample starts with, its colon included when it has one.
String _verbOf(String sample) {
  final m = RegExp(r'^[a-z_]+:?').firstMatch(sample);
  return m == null ? sample : m.group(0)!;
}

String _nameOf(AstNode decl) {
  final cls =
      decl.thisOrAncestorOfType<ClassDeclaration>()?.namePart.typeName.lexeme;
  final name = decl is MethodDeclaration
      ? decl.name.lexeme
      : decl is FunctionDeclaration
          ? decl.name.lexeme
          : '?';
  return cls == null ? name : '$cls.$name';
}

Future<(String, String)?> _bindsTo(
    Workspace ws, Resolver r, Model model, StepOut prev, StepOut s) async {
  final root = s.step.anchor.root;
  final binders = Binders(r, root == 'server' ? ws.server : ws.sdk,
      root == 'server' ? model.roots.serverLib : model.roots.sdkLib);
  for (final f in binders.invokedFunctionFields(prev._resolved!)) {
    for (final b in await binders.functionFieldBindings(f)) {
      if (qualifiedName(b.consumer) == s.step.anchor.symbol) {
        return (
          'field',
          'function-field hop through ${b.field}, bound in ${b.where}'
        );
      }
    }
  }
  for (final f in binders.streamsAddedTo(prev._resolved!)) {
    for (final b in await binders.streamBindings(f)) {
      if (qualifiedName(b.consumer) == s.step.anchor.symbol) {
        return ('stream', 'stream hop through ${b.field}, bound in ${b.where}');
      }
    }
  }
  return null;
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

Future<void> _exitsAndContracts(Workspace ws, Resolver r, StepOut s) async {
  final path = (s.facts.remove('path') as List<AstNode>?) ?? const [];
  final server = s.lane.role == 'server';
  final needsExits =
      server || s.step.contracts.any((c) => c.backing?.isExit ?? false);
  Inventory? inv;
  if (needsExits && path.isNotEmpty && s._resolved != null) {
    inv = await ExitWalker(r, server ? ws.server.dir : ws.sdk.dir).walk(path);
  }
  final roots = ws.roots!;
  if (server && inv != null) {
    final seen = <String, int>{};
    final list = <Map<String, Object?>>[];
    final ids = <String>[];
    for (final e in inv.onPath) {
      final base = '${e.symbol} ${e.guard ?? 'always'} ${e.kind}';
      final n = (seen[base] = (seen[base] ?? 0) + 1);
      final id = n == 1 ? base : '$base #$n';
      ids.add(id);
      final rel = p.relative(e.path, from: ws.server.dir);
      list.add({
        'id': id,
        'kind': e.kind,
        'guard': e.guard,
        'branch': e.branch,
        if (e.pathNotExpanded) 'pathNotExpanded': true,
        'symbol': e.symbol,
        if (e.chain.isNotEmpty) 'chain': e.chain,
        if (e.type != null) 'type': e.type,
        'messages': e.messages,
        'url': _url(roots, 'server', rel, from: e.line),
      });
    }
    s.exits = inv.onPath;
    s.exitIds = ids;
    s.json['exits'] = {
      'complete': inv.incomplete.isEmpty,
      'incomplete': inv.incomplete,
      'list': list,
    };
    s.facts['exits'] = [
      for (final e in list) '${e['kind']} ${e['guard']} ${e['branch']}'
    ];
  }

  final contracts = <Map<String, Object?>>[];
  for (final c in s.step.contracts) {
    final out = <String, Object?>{'kind': c.kind, 'text': c.text};
    contracts.add(out);
    final b = c.backing;
    final what =
        '${s.id}: ${c.kind == 'pre' || c.kind == 'post' ? '${c.kind}condition' : 'claim'} '
        '"${c.isAuthority ? '${c.kind} ' : ''}${c.text}"';
    if (b == null) {
      if (c.isAuthority) {
        s.failures.add('$what cites no extracted exit and no Gherkin clause; '
            'a refusal or authorization claim must be backed');
      } else {
        out['label'] = 'unverified';
        s.unverified++;
      }
      continue;
    }
    if (b.isExit) {
      final all = inv?.exits ?? const <Exit>[];
      final matches = all
          .where((e) =>
              e.symbol == b.exitSymbol &&
              e.guard != null &&
              _norm(e.guard!) == _norm(b.exitGuard!))
          .toList();
      final on = matches.where((e) => e.onPath).toList();
      if (matches.isEmpty) {
        s.failures.add('$what is backed by an exit "${b.exitGuard}" in '
            '${b.exitSymbol} that the extractor does not find');
        continue;
      }
      if (on.isEmpty) {
        final e = matches.first;
        final branch = e.branch.isEmpty ? '(none)' : e.branch.join(' && ');
        s.failures.add('$what is backed by the exit "${b.exitGuard}" in '
            '${b.exitSymbol}, which is on the branch "$branch", not on '
            '${s.id}\'s own path');
        continue;
      }
      final e = on.first;
      if (c.isAuthority &&
          !const {'throw', 'rethrow', 'error'}.contains(e.kind)) {
        s.failures.add('$what is backed by the exit "${b.exitGuard}" in '
            '${b.exitSymbol}, a ${e.kind} exit, which refuses nothing');
        continue;
      }
      out['backing'] = {
        'exit': {
          'symbol': e.symbol,
          'guard': e.guard,
          'kind': e.kind,
          if (e.type != null) 'type': e.type,
          if (server)
            'url': _url(
                roots, 'server', p.relative(e.path, from: ws.server.dir),
                from: e.line),
        }
      };
    } else {
      final root = b.featureRoot!;
      if (root != s.step.anchor.root) {
        s.failures.add('$what is backed by ${b.feature}, which is not from '
            '${s.step.anchor.root == 'server' ? 'at_server' : 'at_client_sdk'}');
        continue;
      }
      final path = b.feature!.substring(root.length + 1);
      final text = (root == 'server' ? ws.server : ws.sdk).read(path);
      if (text == null) {
        s.failures.add('$what cites ${b.feature}, which does not exist');
        continue;
      }
      final m = matchClause(text, b.scenario!, b.clause!);
      if (m.error != null) {
        s.failures.add('$what: ${b.feature}: ${m.error}; no longer finds '
            'clause "${b.clause}"');
        continue;
      }
      out['backing'] = {
        'gherkin': {
          'feature': path,
          'root': root,
          'scenario': b.scenario,
          'clause': b.clause,
          'url':
              _url(roots, root, path, from: root == 'server' ? m.line : null),
        }
      };
    }
    if (c.isAuthority) {
      out['label'] =
          server ? 'enforced by ${s.step.lane}' : 'client-side, best effort';
    } else {
      out['label'] = server ? 'backed' : 'client-side, best effort';
    }
  }
  s.json['contracts'] = contracts;
}

void _render(Workspace ws, Model model, Build b,
    List<Map<String, Object?>> stores, Budgets budgets) {
  final roots = model.roots;
  final inputs = {
    'model': model.hash,
    'server': roots.serverSha,
    'production': roots.productionSha,
  };
  final core = {
    'inputs': inputs,
    'laneNote': b.laneNote,
    'roots': {
      'sdk': roots.sdkGithub,
      'server': roots.serverGithub,
      'serverBranch': roots.serverBranch,
      'serverSha': roots.serverSha,
      'productionTag': roots.productionTag,
    },
    'lanes': [
      for (final l in model.lanes.values)
        {'id': l.id, 'title': l.title, 'role': l.role, 'sublanes': l.sublanes}
    ],
    'lenses': [
      for (final l in model.lenses)
        {
          'id': l.id,
          'title': l.title,
          'summary': l.summary,
          'flows': l.flows,
          'links': [
            for (final k in l.links) {'title': k.title, 'href': k.href}
          ],
        }
    ],
    'stores': stores,
    'flows': [
      for (final f in model.flows)
        {'id': f.id, 'title': f.title, 'lenses': f.lenses}
    ],
  };
  b.files['core.js'] = classicScript('MAP', null, core);
  for (final f in model.flows) {
    final steps = b.steps.where((s) => s.flow == f).toList();
    final flow = {
      'id': f.id,
      'title': f.title,
      'summary': f.summary,
      'lenses': f.lenses,
      'lanes': f.lanes,
      'retired': f.retired,
      'frames': [
        for (final fr in f.frames)
          {'kind': fr.kind, 'label': fr.label, 'from': fr.from, 'to': fr.to}
      ],
      'inputs': inputs,
      'laneNote': b.laneNote,
      'unverified': steps.fold<int>(0, (n, s) => n + s.unverified),
      'steps': [for (final s in steps) s.json],
    };
    b.files['flows/${f.id}.js'] = classicScript('MAP_FLOWS', f.id, flow);
    b.files['flows/${f.id}.md'] = digest(flow);
  }
  final core0 = b.files['core.js']!.length;
  if (core0 > budgets.core) {
    b.failures.add('docs/map/data/core.js would be $core0 bytes, over its '
        'budget of ${budgets.core}');
  }
  for (final f in model.flows) {
    final n = b.files['flows/${f.id}.js']!.length;
    if (n > budgets.flow) {
      b.failures.add('docs/map/data/flows/${f.id}.js would be $n bytes, over '
          'its budget of ${budgets.flow}');
    }
  }
}

/// A Markdown digest of a flow, so a pull request shows the map's change as
/// text.
String digest(Map<String, Object?> flow) {
  final o = StringBuffer();
  final inputs = flow['inputs'] as Map;
  o
    ..writeln('# ${flow['title']}')
    ..writeln()
    ..writeln('Generated by `dart run at_map build`; do not edit.')
    ..writeln()
    ..writeln('- Flow: `${flow['id']}`')
    ..writeln('- Model hash: `${inputs['model']}`')
    ..writeln('- at_server SHA: `${inputs['server']}`')
    ..writeln('- Production SHA: `${inputs['production']}`')
    ..writeln('- ${flow['laneNote']}')
    ..writeln('- Unverified contract lines: ${flow['unverified']}')
    ..writeln();
  for (final s in (flow['steps'] as List).cast<Map>()) {
    final a = s['anchor'] as Map?;
    o
      ..writeln('## ${s['id']} (${s['lane']})')
      ..writeln()
      ..writeln('${s['intent']}')
      ..writeln();
    if (a != null) {
      o.writeln('- Anchor: `${a['root']}:${a['path']}` `${a['symbol']}`');
    }
    final r = s['reached'] as Map?;
    if (r != null) o.writeln('- Reached: ${r['text'] ?? r['kind']}');
    o.writeln(
        '- Body hash: `${s['hash']}`${s['changed'] == true ? ' (changed since reviewed)' : ''}');
    for (final c in ((s['contracts'] as List?) ?? const []).cast<Map>()) {
      o.writeln('- ${c['kind']}: ${c['text']} [${c['label']}]');
    }
    final ex = s['exits'] as Map?;
    if (ex != null) {
      o.writeln(
          '- Exits${ex['complete'] == true ? '' : ' (incomplete: ${(ex['incomplete'] as List).join('; ')})'}:');
      for (final e in (ex['list'] as List).cast<Map>()) {
        final branch = (e['branch'] as List).isEmpty
            ? ''
            : ' on ${(e['branch'] as List).join(' && ')}';
        o.writeln('  - ${e['kind']}${e['type'] == null ? '' : ' ${e['type']}'} '
            'when `${e['guard'] ?? 'always'}`$branch in `${e['symbol']}`'
            '${e['pathNotExpanded'] == true ? ' (path not expanded)' : ''}');
      }
    }
    o.writeln();
  }
  return o.toString();
}
