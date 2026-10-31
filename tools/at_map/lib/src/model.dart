import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'source.dart';

/// The largest model file the generator parses.
const int maxModelFileBytes = 64 * 1024;

/// How many nodes a model file may expand to, aliases followed.
const int maxExpandedNodes = 5000;

/// The longest one-line intent.
const int maxIntentLength = 200;

/// Where the model lives, relative to the SDK checkout.
const String modelDir = 'docs/map/model';

/// A reference into a root's code: a path and a qualified symbol.
class CodeRef {
  /// Creates a reference.
  CodeRef(this.root, this.path, this.symbol, {this.contains});

  /// "sdk" or "server".
  final String root;

  /// The file, relative to its root.
  final String path;

  /// `Class.member`, `Class`, or a top-level name.
  final String symbol;

  /// A token sequence that must occur exactly once in the declaration.
  final String? contains;

  @override
  String toString() => '$root:$path $symbol';
}

/// What backs a claim: an extracted exit or a Gherkin clause.
class Backing {
  /// Creates a backing by an exit.
  Backing.exit(this.exitSymbol, this.exitGuard)
      : feature = null,
        scenario = null,
        clause = null;

  /// Creates a backing by a Gherkin clause.
  Backing.gherkin(this.feature, this.scenario, this.clause)
      : exitSymbol = null,
        exitGuard = null;

  /// The method holding the exit.
  final String? exitSymbol;

  /// The exit's guard, as the extractor prints it.
  final String? exitGuard;

  /// The feature file, as `root:path`.
  final String? feature;

  /// The scenario's title.
  final String? scenario;

  /// The step line, keyword included.
  final String? clause;

  /// Whether this is an exit backing.
  bool get isExit => exitSymbol != null;

  /// The root the backing reads.
  String? get featureRoot => feature?.split(':').first;
}

/// A line of contract text on a step.
class Contract {
  /// Creates a contract line.
  Contract(this.kind, this.text, this.backing);

  /// "refuses", "authorizes", "pre" or "post".
  final String kind;

  /// The public prose.
  final String text;

  /// What backs it, if anything.
  final Backing? backing;

  /// Whether this is a refusal or authorization claim, which must be backed.
  bool get isAuthority => kind == 'refuses' || kind == 'authorizes';
}

/// How a step is reached from the one before it.
class Reached {
  /// Creates a transition.
  Reached(this.kind,
      {this.from,
      this.via = const [],
      this.through,
      this.verb,
      this.sample,
      this.nested = false,
      this.note});

  /// One of entry, call, via, untraced, stream, field, declared, wire, push.
  final String kind;

  /// The step it comes from, when not the previous one.
  final String? from;

  /// Methods called in order between the two steps.
  final List<String> via;

  /// The field or class a hop passes through.
  final CodeRef? through;

  /// The verb of a wire step.
  final String? verb;

  /// A command replayed through the atServer's dispatch.
  final String? sample;

  /// Whether the command arrives inside another, as a batch entry does.
  final bool nested;

  /// Why a declared transition cannot be traced.
  final String? note;

  /// Whether the model said nothing, so a call or a binder must account for
  /// it.
  bool get isDefault => kind == 'call' && from == null && via.isEmpty;
}

/// A link a reader can follow.
class Link {
  /// Creates a link.
  Link(this.title, this.href);

  /// What it says.
  final String title;

  /// Where it goes.
  final String href;
}

/// One step of a flow.
class Step {
  /// Creates a step.
  Step({
    required this.id,
    required this.lane,
    required this.intent,
    required this.anchor,
    required this.reached,
    this.sublane,
    this.contracts = const [],
    this.touches = const [],
    this.links = const [],
    this.navigateTo,
    this.reviewed,
  });

  /// The id, unique and never reused within its flow.
  final String id;

  /// The participant.
  final String lane;

  /// The component inside a client lane.
  final String? sublane;

  /// One line saying what the step does.
  final String intent;

  /// The code the step points at.
  final CodeRef anchor;

  /// How it is reached.
  final Reached reached;

  /// Claims, preconditions and postconditions, in model order.
  final List<Contract> contracts;

  /// Stores the step reads or writes.
  final List<String> touches;

  /// Further reading.
  final List<Link> links;

  /// A flow this step continues in.
  final String? navigateTo;

  /// The body hash a person last read and blessed.
  final String? reviewed;
}

/// A par, opt, loop or alt frame around consecutive steps.
class Frame {
  /// Creates a frame.
  Frame(this.kind, this.label, this.from, this.to);

  /// par, opt, loop or alt.
  final String kind;

  /// The condition or reason.
  final String label;

  /// The first step inside it.
  final String from;

  /// The last step inside it.
  final String to;
}

/// A flow: ordered steps across lanes.
class Flow {
  /// Creates a flow.
  Flow({
    required this.id,
    required this.title,
    required this.summary,
    required this.lenses,
    required this.lanes,
    required this.retired,
    required this.frames,
    required this.steps,
    required this.file,
  });

  /// The id.
  final String id;

  /// A one-line title.
  final String title;

  /// A short paragraph.
  final String summary;

  /// The lenses that open it.
  final List<String> lenses;

  /// The lanes drawn, left to right.
  final List<String> lanes;

  /// Ids once used and never to be reused.
  final List<String> retired;

  /// Frames around steps.
  final List<Frame> frames;

  /// The steps, in order.
  final List<Step> steps;

  /// The model file, relative to the SDK checkout.
  final String file;
}

/// A participant.
class Lane {
  /// Creates a lane.
  Lane(this.id, this.title, this.sublanes);

  /// `<atSign>.<role>[.<instance>]`.
  final String id;

  /// What the page calls it.
  final String title;

  /// Components inside a client lane.
  final List<String> sublanes;

  /// "client" or "server".
  String get role => id.split('.')[1];

  /// The root its code is in.
  String get root => role == 'server' ? 'server' : 'sdk';
}

/// A store a step can touch.
class Store {
  /// Creates a store.
  Store(this.id, this.title, this.anchor);

  /// The id.
  final String id;

  /// What the page calls it.
  final String title;

  /// The class that implements it.
  final CodeRef anchor;
}

/// A starting point for a reader.
class Lens {
  /// Creates a lens.
  Lens(this.id, this.title, this.summary, this.flows, this.links);

  /// The id.
  final String id;

  /// What the page calls it.
  final String title;

  /// A short paragraph.
  final String summary;

  /// The flows it opens with.
  final List<String> flows;

  /// READMEs and examples.
  final List<Link> links;
}

/// The pinned roots.
class Roots {
  /// Creates the roots.
  Roots({
    required this.sdkGithub,
    required this.sdkLib,
    required this.sdkAtCommons,
    required this.serverGithub,
    required this.serverBranch,
    required this.serverSha,
    required this.serverPackage,
    required this.serverLib,
    required this.productionTag,
    required this.productionSha,
  });

  /// `atsign-foundation/at_client_sdk`.
  final String sdkGithub;

  /// The SDK library directories binders search.
  final List<String> sdkLib;

  /// The SDK's at_commons package.
  final String sdkAtCommons;

  /// `atsign-foundation/at_server`.
  final String serverGithub;

  /// The branch the server pin follows.
  final String serverBranch;

  /// The pinned at_server commit.
  final String serverSha;

  /// The package tier 2 resolves.
  final String serverPackage;

  /// The server library directories binders search.
  final List<String> serverLib;

  /// The production tag's name.
  final String productionTag;

  /// The commit the production tag named when it was pinned.
  final String productionSha;
}

/// The whole curated model.
class Model {
  /// Creates the model.
  Model(this.roots, this.lanes, this.stores, this.lenses, this.flows,
      this.ratchet, this.hash);

  /// The pins.
  final Roots roots;

  /// Participants, by id.
  final Map<String, Lane> lanes;

  /// Stores, by id.
  final Map<String, Store> stores;

  /// Lenses, in file order.
  final List<Lens> lenses;

  /// Flows, by id order.
  final List<Flow> flows;

  /// The recorded test-evidence figure: per flow, the exit ids named.
  final Map<String, List<String>> ratchet;

  /// sha256 over every model file a build reads.
  final String hash;
}

/// The result of loading the model: a model, or the failures that stopped
/// it.
class Loaded {
  /// Creates the result.
  Loaded(this.model, this.failures);

  /// The model, when it loaded.
  final Model? model;

  /// Why it did not, or what is wrong with it.
  final List<String> failures;
}

/// A model file that broke a rule.
class _Bad implements Exception {
  _Bad(this.message);
  final String message;
}

/// Loads and validates the model from [sdk].
Loaded loadModel(Tree sdk) {
  final failures = <String>[];
  final files = sdk.filesUnder('$modelDir/', suffix: '.yaml');
  final docs = <String, YamlNode>{};
  for (final f in files) {
    try {
      docs[f] = _parse(sdk, f);
    } on _Bad catch (e) {
      failures.add(e.message);
    } on SourceError catch (e) {
      failures.add(e.toString());
    }
  }
  if (failures.isNotEmpty) return Loaded(null, failures);

  final hashed = files.where((f) => f != '$modelDir/ratchet.yaml').toList();
  final b = BytesBuilder();
  for (final f in hashed) {
    b
      ..add(utf8.encode(f))
      ..addByte(0)
      ..add(utf8.encode(sdk.read(f)!))
      ..addByte(0);
  }
  final hash = sha256.convert(b.takeBytes()).toString();

  T? section<T>(String name, T Function(_R r) read) {
    final path = '$modelDir/$name';
    final node = docs[path];
    if (node == null) {
      failures.add('$path: missing');
      return null;
    }
    try {
      return read(_R(path, node));
    } on _Bad catch (e) {
      failures.add(e.message);
      return null;
    }
  }

  final roots = section('roots.yaml', _roots);
  final lanes = section('lanes.yaml', _lanes);
  final stores = section('stores.yaml', _stores);
  final lenses = section('lenses.yaml', _lenses);
  final ratchet = section('ratchet.yaml', _ratchet);
  final flows = <Flow>[];
  for (final f in files.where((f) => f.startsWith('$modelDir/flows/'))) {
    try {
      flows.add(_flow(_R(f, docs[f]!)));
    } on _Bad catch (e) {
      failures.add(e.message);
    }
  }
  if (roots == null ||
      lanes == null ||
      stores == null ||
      lenses == null ||
      ratchet == null) {
    return Loaded(null, failures);
  }
  flows.sort((a, b) => a.id.compareTo(b.id));
  final model = Model(roots, lanes, stores, lenses, flows, ratchet, hash);
  failures.addAll(_crossCheck(model));
  return Loaded(failures.isEmpty ? model : null, failures);
}

YamlNode _parse(Tree sdk, String path) {
  final text = sdk.read(path)!;
  if (text.length > maxModelFileBytes) {
    throw _Bad('$path: ${text.length} bytes, over the cap of '
        '$maxModelFileBytes');
  }
  final YamlNode node;
  try {
    node = loadYamlNode(text, sourceUrl: Uri.file(path));
  } on YamlException catch (e) {
    throw _Bad('$path: not YAML: ${e.message}');
  }
  var budget = maxExpandedNodes;
  void walk(YamlNode n) {
    if (--budget < 0) {
      throw _Bad('$path: aliases expand past $maxExpandedNodes nodes');
    }
    if (n is YamlMap) {
      for (final e in n.nodes.entries) {
        walk(e.key as YamlNode);
        walk(e.value);
      }
    } else if (n is YamlList) {
      n.nodes.forEach(walk);
    }
  }

  walk(node);
  return node;
}

/// A reader over one YAML node, naming the file and line in every failure.
class _R {
  _R(this.file, this.node);
  final String file;
  final YamlNode node;

  String get where => '$file:${node.span.start.line + 1}';

  Never bad(String message) => throw _Bad('$where: $message');

  YamlMap map(Set<String> keys) {
    final n = node;
    if (n is! YamlMap) bad('expected a mapping');
    for (final k in n.keys) {
      if (!keys.contains(k)) bad('unknown key "$k"');
    }
    return n;
  }

  _R? at(String key) {
    final n = node;
    if (n is! YamlMap) return null;
    final v = n.nodes[key];
    return v == null ? null : _R(file, v);
  }

  _R need(String key) => at(key) ?? bad('missing "$key"');

  String str() {
    final v = node.value;
    if (v is! String) bad('expected a string');
    return v;
  }

  bool boolean() {
    final v = node.value;
    if (v is! bool) bad('expected true or false');
    return v;
  }

  List<_R> list() {
    final n = node;
    if (n is! YamlList) bad('expected a list');
    return [for (final c in n.nodes) _R(file, c)];
  }

  List<String> strings() => [for (final r in list()) r.str()];
}

final _id = RegExp(r'^[a-z][a-z0-9-]*$');
final _sha = RegExp(r'^[0-9a-f]{40}$');
final _laneId = RegExp(r'^(alice|bob)\.(client|server)(\.[a-z][a-z0-9-]*)?$');
final _atSignWord = RegExp(r'@[A-Za-z0-9_\-]+');

String _ident(_R r) {
  final s = r.str();
  if (!_id.hasMatch(s)) r.bad('"$s" is not an id: lower case, digits, -');
  return s;
}

String _prose(_R r, {int max = 2000, bool oneLine = false}) {
  final s = r.str().trim();
  if (s.isEmpty) r.bad('is empty');
  if (s.length > max) r.bad('is ${s.length} characters, over $max');
  if (oneLine && s.contains('\n')) r.bad('must be one line');
  for (final m in _atSignWord.allMatches(s)) {
    final w = m.group(0)!;
    if (w != '@alice' && w != '@bob') {
      r.bad('names $w; lanes are roles held by @alice and @bob, never real '
          'atSigns');
    }
  }
  return s;
}

CodeRef _code(_R r, {bool contains = true}) {
  r.map({'code', 'symbol', if (contains) 'contains'});
  final code = r.need('code').str();
  final colon = code.indexOf(':');
  if (colon < 0) r.bad('code must be root:path');
  final root = code.substring(0, colon);
  final path = code.substring(colon + 1);
  if (root != 'sdk' && root != 'server') r.bad('unknown root "$root"');
  if (!isSafeRelative(path)) r.bad('path "$path" leaves its root');
  final c = r.at('contains')?.str();
  if (c != null && (c.trim().isEmpty || c.length > 200)) {
    r.bad('contains must be 1 to 200 characters');
  }
  return CodeRef(root, path, r.need('symbol').str(), contains: c);
}

Roots _roots(_R r) {
  r.map({'sdk', 'server', 'production'});
  final sdk = r.need('sdk')..map({'github', 'lib', 'at_commons'});
  final server = r.need('server')
    ..map({'github', 'branch', 'sha', 'package', 'lib'});
  final prod = r.need('production')..map({'tag', 'sha'});
  String sha(_R s) {
    final v = s.str();
    if (!_sha.hasMatch(v)) s.bad('expected a 40-character SHA');
    return v;
  }

  String github(_R s) {
    final v = s.str();
    if (!RegExp(r'^atsign-foundation/[A-Za-z0-9_.-]+$').hasMatch(v)) {
      s.bad('must be a repository under atsign-foundation');
    }
    return v;
  }

  return Roots(
    sdkGithub: github(sdk.need('github')),
    sdkLib: sdk.need('lib').strings(),
    sdkAtCommons: sdk.need('at_commons').str(),
    serverGithub: github(server.need('github')),
    serverBranch: server.need('branch').str(),
    serverSha: sha(server.need('sha')),
    serverPackage: server.need('package').str(),
    serverLib: server.need('lib').strings(),
    productionTag: prod.need('tag').str(),
    productionSha: sha(prod.need('sha')),
  );
}

Map<String, Lane> _lanes(_R r) {
  r.map({'lanes'});
  final out = <String, Lane>{};
  for (final l in r.need('lanes').list()) {
    l.map({'id', 'title', 'sublanes'});
    final id = l.need('id').str();
    if (!_laneId.hasMatch(id)) {
      l.need('id').bad('lane "$id" is not <alice|bob>.<client|server>'
          '[.<instance>]');
    }
    if (out.containsKey(id)) l.bad('lane "$id" twice');
    out[id] = Lane(id, _prose(l.need('title'), max: 80),
        l.at('sublanes')?.strings() ?? const []);
  }
  return out;
}

Map<String, Store> _stores(_R r) {
  r.map({'stores'});
  final out = <String, Store>{};
  for (final s in r.need('stores').list()) {
    s.map({'id', 'title', 'anchor'});
    final id = _ident(s.need('id'));
    out[id] = Store(id, _prose(s.need('title'), max: 80),
        _code(s.need('anchor'), contains: false));
  }
  return out;
}

List<Link> _links(_R? r) => [
      for (final l in r?.list() ?? <_R>[])
        () {
          l.map({'title', 'href'});
          return Link(_prose(l.need('title'), max: 120), l.need('href').str());
        }()
    ];

List<Lens> _lenses(_R r) {
  r.map({'lenses'});
  return [
    for (final l in r.need('lenses').list())
      () {
        l.map({'id', 'title', 'summary', 'flows', 'links'});
        return Lens(
            _ident(l.need('id')),
            _prose(l.need('title'), max: 80),
            _prose(l.need('summary')),
            l.need('flows').strings(),
            _links(l.at('links')));
      }()
  ];
}

Map<String, List<String>> _ratchet(_R r) {
  final n = r.node;
  if (n is! YamlMap) r.bad('expected a mapping of flow to named exits');
  final out = <String, List<String>>{};
  for (final k in n.keys) {
    final f = r.need(k as String)..map({'named', 'exits'});
    final named = f.need('named').node.value;
    final exits = f.need('exits').strings();
    if (named is! int || named != exits.length) {
      f.bad('named must equal the number of exits listed');
    }
    out[k] = exits;
  }
  return out;
}

Backing _backing(_R r) {
  r.map({'exit', 'gherkin'});
  final e = r.at('exit');
  final g = r.at('gherkin');
  if ((e == null) == (g == null)) r.bad('give exactly one of exit, gherkin');
  if (e != null) {
    e.map({'symbol', 'guard'});
    return Backing.exit(e.need('symbol').str(), e.need('guard').str());
  }
  g!.map({'feature', 'scenario', 'clause'});
  final feature = g.need('feature').str();
  final colon = feature.indexOf(':');
  if (colon < 0 ||
      !{'sdk', 'server'}.contains(feature.substring(0, colon)) ||
      !isSafeRelative(feature.substring(colon + 1))) {
    g.need('feature').bad('feature must be sdk:path or server:path');
  }
  return Backing.gherkin(
      feature, g.need('scenario').str(), g.need('clause').str());
}

Reached _reached(_R? r) {
  if (r == null) return Reached('call');
  final n = r.node;
  if (n.value == 'entry') return Reached('entry');
  r.map({'from', 'via', 'hop', 'wire', 'sample', 'nested', 'push', 'note'});
  final from = r.at('from') == null ? null : _ident(r.at('from')!);
  final viaNode = r.at('via');
  final note = r.at('note')?.str();
  if (r.at('wire') != null) {
    final sample = r.need('sample').str();
    if (sample.length > 400 || sample.contains('\n')) {
      r.need('sample').bad('a sample is one line of at most 400 characters');
    }
    return Reached('wire',
        from: from,
        via: viaNode?.strings() ?? const [],
        verb: r.need('wire').str(),
        sample: sample,
        nested: r.at('nested')?.boolean() ?? false);
  }
  if (r.at('push') != null) {
    return Reached('push', from: from, note: r.need('push').str());
  }
  final hop = r.at('hop');
  if (hop != null) {
    hop.map({'stream', 'field', 'declared'});
    final kinds = ['stream', 'field', 'declared']
        .where((k) => hop.at(k) != null)
        .toList();
    if (kinds.length != 1) {
      hop.bad('give exactly one of stream, field, declared');
    }
    return Reached(kinds.single,
        from: from,
        via: viaNode?.strings() ?? const [],
        through: _code(hop.need(kinds.single), contains: false),
        note: note);
  }
  if (viaNode != null && viaNode.node.value == 'untraced') {
    if (note == null) r.bad('an untraced via needs a note saying why');
    return Reached('untraced', from: from, note: note);
  }
  final via = viaNode?.strings() ?? const <String>[];
  return Reached(via.isEmpty ? 'call' : 'via', from: from, via: via);
}

Step _step(_R r) {
  r.map({
    'id', 'lane', 'sublane', 'intent', 'anchor', 'reached', 'claims', 'pre',
    'post', 'touches', 'links', 'navigateTo', 'reviewed' //
  });
  final contracts = <Contract>[];
  for (final c in r.at('claims')?.list() ?? <_R>[]) {
    c.map({'refuses', 'authorizes', 'backing'});
    final kind = c.at('refuses') != null ? 'refuses' : 'authorizes';
    if (c.at(kind) == null ||
        (c.at('refuses') != null && c.at('authorizes') != null)) {
      c.bad('a claim is exactly one of refuses, authorizes');
    }
    contracts.add(Contract(kind, _prose(c.need(kind), max: 300),
        c.at('backing') == null ? null : _backing(c.need('backing'))));
  }
  for (final kind in ['pre', 'post']) {
    for (final c in r.at(kind)?.list() ?? <_R>[]) {
      c.map({'text', 'backing'});
      contracts.add(Contract(kind, _prose(c.need('text'), max: 300),
          c.at('backing') == null ? null : _backing(c.need('backing'))));
    }
  }
  return Step(
    id: _ident(r.need('id')),
    lane: r.need('lane').str(),
    sublane: r.at('sublane')?.str(),
    intent: _prose(r.need('intent'), max: maxIntentLength, oneLine: true),
    anchor: _code(r.need('anchor')),
    reached: _reached(r.at('reached')),
    contracts: contracts,
    touches: r.at('touches')?.strings() ?? const [],
    links: _links(r.at('links')),
    navigateTo: r.at('navigateTo')?.str(),
    reviewed: r.at('reviewed')?.str(),
  );
}

Flow _flow(_R r) {
  r.map({
    'id', 'title', 'summary', 'lenses', 'lanes', 'retired', 'frames', 'steps' //
  });
  final frames = [
    for (final f in r.at('frames')?.list() ?? <_R>[])
      () {
        f.map({'kind', 'label', 'from', 'to'});
        final kind = f.need('kind').str();
        if (!{'par', 'opt', 'loop', 'alt'}.contains(kind)) {
          f.need('kind').bad('a frame is par, opt, loop or alt');
        }
        return Frame(kind, _prose(f.need('label'), max: 120),
            f.need('from').str(), f.need('to').str());
      }()
  ];
  final id = _ident(r.need('id'));
  if (r.file != '$modelDir/flows/$id.yaml') {
    r.bad('flow "$id" must live in $modelDir/flows/$id.yaml');
  }
  return Flow(
    id: id,
    title: _prose(r.need('title'), max: 120, oneLine: true),
    summary: _prose(r.need('summary')),
    lenses: r.need('lenses').strings(),
    lanes: r.need('lanes').strings(),
    retired: r.at('retired')?.strings() ?? const [],
    frames: frames,
    steps: [for (final s in r.need('steps').list()) _step(s)],
    file: r.file,
  );
}

List<String> _crossCheck(Model m) {
  final out = <String>[];
  final flowIds = {for (final f in m.flows) f.id};
  for (final lens in m.lenses) {
    for (final f in lens.flows) {
      if (!flowIds.contains(f)) out.add('lens ${lens.id}: no flow "$f"');
    }
  }
  for (final f in m.flows) {
    final ids = <String>{};
    for (final l in f.lanes) {
      if (!m.lanes.containsKey(l)) out.add('${f.id}: no lane "$l"');
    }
    for (final s in f.steps) {
      final sid = '${f.id}.${s.id}';
      if (!ids.add(s.id)) out.add('$sid: step id used twice');
      if (f.retired.contains(s.id)) {
        out.add('$sid: "${s.id}" is retired in ${f.file} and may not be '
            'reused');
      }
      final lane = m.lanes[s.lane];
      if (lane == null || !f.lanes.contains(s.lane)) {
        out.add('$sid: lane "${s.lane}" is not one of the flow\'s lanes');
        continue;
      }
      if (s.anchor.root != lane.root) {
        out.add('$sid: a ${lane.role} step anchors in ${lane.root}, not '
            '${s.anchor.root}');
      }
      if (s.sublane != null && !lane.sublanes.contains(s.sublane)) {
        out.add('$sid: lane ${s.lane} has no sublane "${s.sublane}"');
      }
      for (final t in s.touches) {
        if (!m.stores.containsKey(t)) out.add('$sid: no store "$t"');
      }
      if (s.navigateTo != null && !flowIds.contains(s.navigateTo)) {
        out.add('$sid: navigateTo names no flow "${s.navigateTo}"');
      }
      final from = s.reached.from;
      if (from != null && !ids.contains(from)) {
        out.add('$sid: reached from "$from", which is not an earlier step');
      }
    }
    if (f.steps.isEmpty || f.steps.first.reached.kind != 'entry') {
      out.add('${f.id}: the first step must be reached: entry');
    }
    for (final s in f.steps.skip(1)) {
      if (s.reached.kind == 'entry') {
        out.add('${f.id}.${s.id}: only the first step is the entry');
      }
    }
    for (final fr in f.frames) {
      if (!ids.contains(fr.from) || !ids.contains(fr.to)) {
        out.add('${f.id}: frame "${fr.label}" names a step that is not in '
            'the flow');
      }
    }
  }
  return out;
}
