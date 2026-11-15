import 'dart:io';

import 'package:test/test.dart';

/// The test trees the scan reads, named from this package's directory, each
/// with the fewest Dart files it is known to hold.
const _trees = {
  'test': 20,
  '../at_auth/test': 20,
  '../at_client/test': 100,
  '../at_client_flutter/test': 10,
};

/// This file, whose controls hold every spelling the scan forbids.
const _self = 'test/unit_tests_stay_on_loopback_test.dart';

/// at_client's helper that refuses an atDirectory off the loopback interface.
const _atClientTransport = '../at_client/test/test_utils/transport.dart';

/// at_client's hand-run samples, which name the environment they run against.
const _atClientSamples = '../at_client/test/samples/';

/// The one test file that may extend `AtsignFlows`.
const _loopbackFlows = '../at_client_flutter/test/loopback_flows.dart';

/// The arguments naming an atDirectory host that a test may build a finder
/// with.
const _loopbackArguments = {
  "'127.0.0.1'",
  '"127.0.0.1"',
  "'localhost'",
  'InternetAddress.loopbackIPv4.address',
};

/// The at_activate commands that open a connection to the atDirectory the
/// command line names, or to root.atsign.org when it names none.
const _connectingCommands =
    'otp|list|approve|spp|fetch|deny|revoke|unrevoke|delete|interactive|auto|'
    'status';

/// The dialogs that run the lifecycle verbs, through `flows`.
const _dialogs = ['PkamDialog', 'CramDialog', 'ApkamActivationDialog'];

/// The text of the bracketed list or argument list that opens just before
/// [start] in [source], up to the bracket that closes it.
String bracketedAt(String source, int start,
    {String open = '(', String close = ')'}) {
  var depth = 1;
  for (var i = start; i < source.length; i++) {
    final c = source[i];
    if (c == open) depth++;
    if (c == close && --depth == 0) return source.substring(start, i);
  }
  return source.substring(start);
}

/// [arguments] with everything inside a nested bracket taken out, leaving
/// the top-level arguments' names.
String topLevel(String arguments) {
  final out = <String>[];
  var depth = 0;
  for (final c in arguments.split('')) {
    if ('([{'.contains(c)) depth++;
    if (depth == 0) out.add(c);
    if (')]}'.contains(c)) depth--;
  }
  return out.join();
}

/// The hosts a test may name its atDirectory on.
const _loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// Whether [root], an atDirectory named as `host`, `host:port` or
/// `[host]:port`, any of them after `proxy:`, is on a loopback host.
bool _loopbackRoot(String root) {
  final address = root.startsWith('proxy:') ? root.substring(6) : root;
  final host = RegExp(r'^\[([^\]]*)\](?::|$)').firstMatch(address)?.group(1) ??
      (address == '::1' ? address : address.split(':').first);
  return _loopbackHosts.contains(host);
}

/// Whether [path] is in at_client_cli's own tree, or names no file.
bool _atActivateTree(String path) => !path.startsWith('../');

/// What in [source], the text of the test file at [path], could make a test
/// reach an atDirectory off the loopback interface: a finder built for
/// another host, or by a tear-off or a subclass; a connection factory
/// invoked with no finder; the real lifecycle verbs without `LoopbackFlows`,
/// through `AtsignFlows` itself, a subclass, an implementation that is no
/// `Mock`, or a dialog built without its own `flows`; and, in
/// at_client_cli's own tree, a root named off the loopback interface or
/// at_activate run for a connecting command with no root, which then uses
/// root.atsign.org.
List<String> offTheLoopbackIn(String source, {String path = ''}) => [
      for (final m in RegExp(
              r'\b(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\s*\(\s*([^,)]+)')
          .allMatches(source))
        if (!_loopbackArguments.contains(m.group(2)!.trim()))
          'a ${m.group(1)} for ${m.group(2)!.trim()}',
      for (final m in RegExp(
              r'\b(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\.new\b|'
              r'extends\s+(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\b')
          .allMatches(source))
        'a finder torn off or subclassed at offset ${m.start}',
      for (final m
          in RegExp(r'\b(secureSocketLookUps|lookUpsFor|proxyLookUps)\s*\(')
              .allMatches(source))
        if (_invokedWithoutFinder(source, m.end))
          '${m.group(1)} invoked with no finder',
      for (final m
          in RegExp(r'AtLookUp\.withSecureSocket\s*\(').allMatches(source))
        if (!bracketedAt(source, m.end).contains('secondaryAddressFinder:'))
          'AtLookUp.withSecureSocket with no finder',
      if (_atActivateTree(path)) ...[
        for (final m in RegExp(
                r'''(?:'-r'|"-r"|'--root-server'|"--root-server"|rootDomain:|\.rootDomain\s*=|AtRootDomain\()\s*,?\s*(['"])(.*?)\1''')
            .allMatches(source))
          if (!_loopbackRoot(m.group(2)!)) 'the root ${m.group(2)}',
        for (final m in RegExp('''\\[\\s*['"]($_connectingCommands)['"]''')
            .allMatches(source))
          if (_commandLineWithoutRoot(
              bracketedAt(source, m.start + 1, open: '[', close: ']')))
            'at_activate ${m.group(1)} with no root',
      ],
      for (final m
          in RegExp(r'\bAtsignFlows\s*(?:\(|\.new\b)').allMatches(source))
        'the real verbs at offset ${m.start}',
      if (path != _loopbackFlows)
        for (final m in RegExp(r'extends\s+AtsignFlows\b').allMatches(source))
          'a subclass of AtsignFlows at offset ${m.start}',
      for (final m in RegExp(
              r'class\s+\w+\s+(?:extends\s+(\w+)\s+)?implements\s+AtsignFlows\b')
          .allMatches(source))
        if (m.group(1) != 'Mock')
          'AtsignFlows implemented at offset ${m.start}',
      for (final dialog in _dialogs)
        for (final m in RegExp('\\b$dialog(\\.show)?\\(').allMatches(source))
          if (m.group(1) != null)
            '$dialog.show at offset ${m.start}'
          else if (!RegExp(r'(^|[,\s])flows\s*:')
              .hasMatch(topLevel(bracketedAt(source, m.end))))
            '$dialog with no flows at offset ${m.start}',
    ];

/// Whether [list], the elements of a list literal, is a command line naming
/// an atSign and no root.
bool _commandLineWithoutRoot(String list) =>
    RegExp(r'''['"](-a|--atsign)['"]''').hasMatch(list) &&
    !RegExp(r'''['"](-r|--root-server)['"]''').hasMatch(list);

/// Whether the factory whose arguments open at [start] is invoked at once,
/// with arguments naming no finder.
bool _invokedWithoutFinder(String source, int start) {
  final factoryArguments = bracketedAt(source, start);
  final after = start + factoryArguments.length + 1;
  final rest = source.substring(after);
  if (!rest.trimLeft().startsWith('(')) return false;
  final open = after + rest.indexOf('(') + 1;
  return !bracketedAt(source, open).contains('secondaryAddressFinder:');
}

/// What is wrong with the test file at [path], whose text is [source], as to
/// the hand-run samples: a test among them, or a file outside them that
/// imports their finder.
List<String> samplesOffencesIn(String path, String source) {
  if (path.startsWith(_atClientSamples)) {
    // NOTE: samples are run by hand against the environment they name;
    // dart test runs only *_test.dart files, so none may be one.
    return [
      if (path.endsWith('_test.dart')) 'a test among the hand-run samples'
    ];
  }
  return [
    if (source.contains('sample_transport.dart'))
      "imports the hand-run samples' finder"
  ];
}

/// Everything wrong with the test file at [path], one of the scanned trees
/// followed by the file's path within it, whose text is [source].
List<String> offencesIn(String path, String source) => [
      ...samplesOffencesIn(path, source),
      if (path != _atClientTransport && !path.startsWith(_atClientSamples))
        ...offTheLoopbackIn(source, path: path),
    ];

/// No unit test in at_auth, at_client, at_client_cli or at_client_flutter
/// reaches an atDirectory off the loopback interface, runs at_activate
/// somewhere that uses root.atsign.org, or reaches the lifecycle verbs
/// without `LoopbackFlows`.
void main() {
  test('the scan catches each way to another atDirectory, and passes loopback',
      () {
    expect(
        offTheLoopbackIn([
          "CacheableSecondaryAddressFinder('root.atsign.org', 64)",
          'final f = SecondaryUrlFinder.new;',
          'lookUpsFor(root)(atSign: a, rootDomain: r, authenticator: null)',
          "CLIBase(atSign: a, nameSpace: n, rootDomain: 'root.atsign.org')",
          "['otp', '-a', '@alice']",
          "['-a', '@alice', '-r', 'root.atsign.wtf']",
          'AtLookUp.withSecureSocket(atSign: a, rootDomain: r)',
          'const AtsignFlows();',
          'class _Fake implements AtsignFlows {}',
          'CramDialog(atSign: a, preference: f(flows: x));',
          'PkamDialog.show(context, atSign: a);',
        ].join('\n')),
        hasLength(11));
    expect(offTheLoopbackIn("for (final c in ['otp', 'list']) {}"), isEmpty,
        reason: 'a list of command names is no command line');
    expect(
        offTheLoopbackIn('final t = CacheableSecondaryAddressFinder;'), isEmpty,
        reason: 'a type literal constructs nothing: only .new tears off the '
            'constructor');
    expect(
        offTheLoopbackIn([
          "['otp', '-a', '@alice', '-r', '127.0.0.1:\$port']",
          "CLIBase(atSign: a, rootDomain: 'proxy:127.0.0.1:\${server.port}')",
          "['onboard', '-a', '@alice', '-y']",
          'lookUps: lookUpsFor(preference.rootDomain),',
          "CacheableSecondaryAddressFinder('127.0.0.1', port)",
          'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: '
              'null, secondaryAddressFinder: f)',
          'lookUps: secureSocketLookUps(),',
          'AtLookUp.withSecureSocket(atSign: a, secondaryAddressFinder: f)',
          'PkamDialog(atSign: a, keys: k, flows: f(x))',
          'class _Mock extends Mock implements AtsignFlows {}',
          'isA<CacheableSecondaryAddressFinder>()',
        ].join('\n')),
        isEmpty);
  });

  test(
      'the scan judges a root by its whole host, reads a root set by '
      'assignment, and catches each spelling of the real verbs', () {
    for (final (example, reason) in [
      (
        "CLIBase(atSign: a, rootDomain: 'localhost.example.com')",
        'a host that begins with localhost is not localhost'
      ),
      (
        "['-a', '@alice', '-r', '127.0.0.1.nip.io:64']",
        'a host that begins with 127.0.0.1 is not 127.0.0.1'
      ),
      (
        "AtClientPreference()..rootDomain = 'root.atsign.org'",
        'a root assigned in a cascade is judged by its host'
      ),
      ('final f = AtsignFlows.new;', 'a tear-off constructs the real verbs'),
      ('const AtsignFlows ( );', 'whitespace before the arguments'),
      ('flows: AtsignFlows(\n),', 'a constructor call split across lines'),
    ]) {
      expect(offTheLoopbackIn(example), hasLength(1), reason: reason);
    }
    for (final (example, reason) in [
      ("..rootDomain = '127.0.0.1'", 'a loopback root assigned in a cascade'),
      (
        '..rootDomain = InternetAddress.loopbackIPv4.address',
        'a root that is no literal is not judged'
      ),
      ("rootDomain: 'localhost:64'", 'localhost with a port'),
      ("rootDomain: '[::1]:\$port'", 'a bracketed IPv6 loopback with a port'),
      ('final flows = MockAtsignFlows();', 'a mock of the real verbs'),
      ('flows: const LoopbackFlows(),', 'the verbs that refuse off loopback'),
    ]) {
      expect(offTheLoopbackIn(example), isEmpty, reason: reason);
    }
  });

  test('the scan keeps each exemption, and the at_activate rules, to its tree',
      () {
    for (final atActivate in [
      "AtRootDomain('example.com')",
      "['otp', '-a', '@alice']",
    ]) {
      expect(
          offTheLoopbackIn(atActivate, path: 'test/a_test.dart'), hasLength(1),
          reason: atActivate);
      expect(offTheLoopbackIn(atActivate, path: '../at_auth/test/a_test.dart'),
          isEmpty,
          reason: atActivate);
    }

    const subclass = 'class _Real extends AtsignFlows { const _Real(); }';
    expect(offTheLoopbackIn(subclass, path: _loopbackFlows), isEmpty);
    expect(offTheLoopbackIn(subclass, path: 'test/loopback_flows.dart'),
        hasLength(1));

    const finder = "CacheableSecondaryAddressFinder('example.com', 64)";
    expect(offencesIn(_atClientTransport, finder), isEmpty);
    expect(offencesIn('${_atClientSamples}lookup.dart', finder), isEmpty);
    for (final path in [
      'test/test_utils/transport.dart',
      '../at_auth/test/test_utils/transport.dart',
      '../at_client/test/test_utils/mocks.dart',
      '../at_client_flutter/test/samples/lookup.dart',
    ]) {
      expect(offencesIn(path, finder), hasLength(1), reason: path);
    }
  });

  test('the scan keeps the hand-run samples to themselves', () {
    expect(
        samplesOffencesIn('${_atClientSamples}a_test.dart', ''), hasLength(1));
    expect(samplesOffencesIn('${_atClientSamples}a.dart', ''), isEmpty);
    expect(
        samplesOffencesIn('../at_client/test/a_test.dart',
            "import 'samples/sample_transport.dart';"),
        hasLength(1));
    expect(
        samplesOffencesIn('../at_client/test/a_test.dart',
            "import 'test_utils/transport.dart';"),
        isEmpty);
  });

  test(
      'nothing in a test in any of the four packages reaches an atDirectory '
      'off the loopback interface', () {
    final read = <String, int>{};
    final offenders = <String>[];
    for (final MapEntry(key: tree, value: atLeast) in _trees.entries) {
      final root = Directory(tree).resolveSymbolicLinksSync();
      final files = [
        for (final file in Directory(root).listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            (
              path: '$tree/${file.path.substring(root.length + 1)}'
                  .replaceAll(Platform.pathSeparator, '/'),
              file: file,
            ),
      ].where((f) => f.path != _self).toList();
      read[tree] = files.length;
      expect(files.length, greaterThan(atLeast),
          reason: 'the scan reads $tree: ${files.length} files');
      for (final f in files) {
        for (final found in offencesIn(f.path, f.file.readAsStringSync())) {
          offenders.add('${f.path}: $found');
        }
      }
    }
    expect(read.keys, [
      'test',
      '../at_auth/test',
      '../at_client/test',
      '../at_client_flutter/test',
    ]);
    expect(offenders, isEmpty, reason: 'files read in each tree: $read');
  });
}
