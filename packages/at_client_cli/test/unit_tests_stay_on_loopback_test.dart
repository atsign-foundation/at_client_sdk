import 'dart:io';

import 'package:test/test.dart';

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

bool _loopbackRoot(String root) =>
    root.contains('127.0.0.1') || root.contains('localhost');

/// What in [source] could make a test reach an atDirectory off the loopback
/// interface: a finder built for another host, or by a tear-off or a
/// subclass; a connection factory invoked with no finder; a root named off
/// the loopback interface; and at_activate run for a connecting command
/// with no root, which then uses root.atsign.org.
List<String> offTheLoopbackIn(String source) => [
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
      for (final m in RegExp(
              r'''(?:'-r'|"-r"|'--root-server'|"--root-server"|rootDomain:|AtRootDomain\()\s*,?\s*(['"])(.*?)\1''')
          .allMatches(source))
        if (!_loopbackRoot(m.group(2)!)) 'the root ${m.group(2)}',
      for (final m in RegExp('''\\[\\s*['"]($_connectingCommands)['"]''')
          .allMatches(source))
        if (_commandLineWithoutRoot(
            bracketedAt(source, m.start + 1, open: '[', close: ']')))
          'at_activate ${m.group(1)} with no root',
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

/// No at_client_cli unit test names an atDirectory off the loopback
/// interface, or runs at_activate somewhere that uses root.atsign.org.
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
        ].join('\n')),
        hasLength(6));
    expect(offTheLoopbackIn("for (final c in ['otp', 'list']) {}"), isEmpty,
        reason: 'a list of command names is no command line');
    expect(
        offTheLoopbackIn([
          "['otp', '-a', '@alice', '-r', '127.0.0.1:\$port']",
          "CLIBase(atSign: a, rootDomain: 'proxy:127.0.0.1:\${server.port}')",
          "['onboard', '-a', '@alice', '-y']",
          'lookUps: lookUpsFor(preference.rootDomain),',
        ].join('\n')),
        isEmpty);
  });

  test('the scan catches each spelling of each way on its own', () {
    for (final way in [
      "CacheableSecondaryAddressFinder('example.com', 64)",
      "SecondaryUrlFinder('example.com', 64)",
      'final f = CacheableSecondaryAddressFinder.new;',
      'final f = SecondaryUrlFinder.new;',
      'class Mine extends CacheableSecondaryAddressFinder {}',
      'class Mine extends SecondaryUrlFinder {}',
      'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: null)',
      'lookUpsFor(root)(atSign: a, rootDomain: r, authenticator: null)',
      'proxyLookUps(root)(atSign: a, rootDomain: r, authenticator: null)',
      'AtLookUp.withSecureSocket(atSign: a, rootDomain: r)',
      "'-r', 'example.com'",
      '"-r", "example.com"',
      "'--root-server', 'example.com'",
      '"--root-server", "example.com"',
      "rootDomain: 'example.com'",
      "AtRootDomain('example.com')",
      for (final command in [
        'otp',
        'list',
        'approve',
        'spp',
        'fetch',
        'deny',
        'revoke',
        'unrevoke',
        'delete',
        'interactive',
        'auto',
        'status',
      ])
        "['$command', '-a', '@alice']",
      "['otp', '--atsign', '@alice']",
    ]) {
      expect(offTheLoopbackIn(way), hasLength(1), reason: way);
    }
    expect(
        offTheLoopbackIn(
            "['otp', '--atsign', '@alice', '--root-server', '127.0.0.1:1']"),
        isEmpty,
        reason: '--root-server names the root');
  });

  test('nothing in a test reaches an atDirectory off the loopback interface',
      () {
    final self = File('test/unit_tests_stay_on_loopback_test.dart').absolute;
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && f.absolute.path != self.path)
        .toList();
    expect(files.length, greaterThan(20),
        reason: 'the scan reads the test tree: ${files.length} files');

    final offenders = <String>[
      for (final file in files)
        for (final found in offTheLoopbackIn(file.readAsStringSync()))
          '${file.path}: $found',
    ];
    expect(offenders, isEmpty);
  });
}
