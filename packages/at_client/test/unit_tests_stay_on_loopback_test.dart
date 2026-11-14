import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:test/test.dart';

import 'test_utils/transport.dart';

/// The arguments naming an atDirectory host that a test may build a finder
/// with.
const _loopbackArguments = {
  "'127.0.0.1'",
  '"127.0.0.1"',
  "'localhost'",
  'InternetAddress.loopbackIPv4.address',
};

/// The text of the argument list that opens just before [start] in
/// [source], up to its closing parenthesis.
String argumentsAt(String source, int start) {
  var depth = 1;
  for (var i = start; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return source.substring(start, i);
  }
  return source.substring(start);
}

/// What in [source] could make a test reach an atDirectory off the loopback
/// interface: a finder built for another host, or by a tear-off or a
/// subclass, and a connection factory invoked with no finder, which builds
/// one for whatever root it is given.
List<String> offTheLoopbackIn(String source) => [
      for (final m in RegExp(
              r'\b(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\s*\(\s*([^,)]+)')
          .allMatches(source))
        if (!_loopbackArguments.contains(m.group(2)!.trim()))
          'a ${m.group(1)} for ${m.group(2)!.trim()}',
      for (final m in RegExp(
              r'\b(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\.new\b')
          .allMatches(source))
        'a ${m.group(1)} torn off',
      for (final m in RegExp(
              r'extends\s+(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\b')
          .allMatches(source))
        'a subclass of ${m.group(1)}',
      for (final m
          in RegExp(r'\b(secureSocketLookUps|lookUpsFor|proxyLookUps)\s*\(')
              .allMatches(source))
        if (_invokedWithoutFinder(source, m.end))
          '${m.group(1)} invoked with no finder',
      for (final m
          in RegExp(r'AtLookUp\.withSecureSocket\s*\(').allMatches(source))
        if (!argumentsAt(source, m.end).contains('secondaryAddressFinder:'))
          'AtLookUp.withSecureSocket with no finder',
    ];

/// Whether the factory whose arguments open at [start] is invoked at once,
/// with arguments naming no finder.
bool _invokedWithoutFinder(String source, int start) {
  final factoryArguments = argumentsAt(source, start);
  final after = start + factoryArguments.length + 1;
  final rest = source.substring(after);
  if (!rest.trimLeft().startsWith('(')) return false;
  final open = after + rest.indexOf('(') + 1;
  return !argumentsAt(source, open).contains('secondaryAddressFinder:');
}

/// No unit test names an atDirectory off the loopback interface: the shared
/// helpers refuse one before anything connects, and nothing in a test
/// reaches one another way.
void main() {
  final sep = Platform.pathSeparator;

  test('the shared helpers refuse an atDirectory off the loopback interface',
      () {
    expect(
        () => atDirectoryOf(AtClientPreference()),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('root.atsign.org:64'))));
    expect(
        atDirectoryOf(AtClientPreference()
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = 1),
        isA<CacheableSecondaryAddressFinder>(),
        reason: 'the control: a loopback atDirectory is handed back');
  });

  test('the scan catches each way past the helpers, and passes loopback', () {
    expect(
        offTheLoopbackIn([
          "CacheableSecondaryAddressFinder('root.atsign.org', 64)",
          "SecondaryUrlFinder('root.atsign.org', 64)",
          'final f = CacheableSecondaryAddressFinder.new;',
          'class Mine extends CacheableSecondaryAddressFinder {}',
          'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: null)',
          'AtLookUp.withSecureSocket(atSign: a, rootDomain: r)',
        ].join('\n')),
        hasLength(6));
    expect(
        offTheLoopbackIn([
          "CacheableSecondaryAddressFinder('127.0.0.1', port)",
          'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: '
              'null, secondaryAddressFinder: f)',
          'lookUps: secureSocketLookUps(),',
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
    ]) {
      expect(offTheLoopbackIn(way), hasLength(1), reason: way);
    }
  });

  test('nothing in a test reaches an atDirectory off the loopback interface',
      () {
    final self = File('test/unit_tests_stay_on_loopback_test.dart').absolute;
    final helper = File('test/test_utils/transport.dart').absolute;
    final samples = '${sep}test${sep}samples$sep';
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && f.absolute.path != self.path)
        .toList();
    expect(files.length, greaterThan(100),
        reason: 'the scan reads the test tree: ${files.length} files');

    final offenders = <String>[
      for (final file in files)
        if (file.absolute.path.contains(samples)) ...[
          // NOTE: samples are run by hand against the environment they name;
          // dart test runs only *_test.dart files, so none may be one.
          if (file.path.endsWith('_test.dart'))
            '${file.path}: a test among the hand-run samples',
        ] else ...[
          if (file.readAsStringSync().contains('sample_transport.dart'))
            '${file.path}: imports the hand-run samples\' finder',
          if (file.absolute.path != helper.path)
            for (final found in offTheLoopbackIn(file.readAsStringSync()))
              '${file.path}: $found',
        ],
    ];
    expect(offenders, isEmpty);
  });
}
