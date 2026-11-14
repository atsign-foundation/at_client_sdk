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
/// subclass, and a connection built or invoked with no finder, which then
/// builds one for whatever root it is given.
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
          in RegExp(r'\bsecureSocketLookUps\s*\(\s*\)\s*\(').allMatches(source))
        if (!argumentsAt(source, m.end).contains('secondaryAddressFinder:'))
          'secureSocketLookUps invoked with no finder',
      for (final m
          in RegExp(r'AtLookUp\.withSecureSocket\s*\(').allMatches(source))
        if (!argumentsAt(source, m.end).contains('secondaryAddressFinder:'))
          'AtLookUp.withSecureSocket with no finder',
    ];

/// No at_auth unit test names an atDirectory off the loopback interface.
void main() {
  test('the scan catches each way to another atDirectory, and passes loopback',
      () {
    expect(
        offTheLoopbackIn([
          "CacheableSecondaryAddressFinder('root.atsign.org', 64)",
          "SecondaryUrlFinder('root.atsign.org', 64)",
          'final f = CacheableSecondaryAddressFinder.new;',
          'class Mine extends SecondaryUrlFinder {}',
          'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: null)',
          'AtLookUp.withSecureSocket(atSign: a, rootDomain: r)',
        ].join('\n')),
        hasLength(6));
    expect(
        offTheLoopbackIn([
          "CacheableSecondaryAddressFinder('127.0.0.1', port)",
          'AtLookUp.withSecureSocket(atSign: a, secondaryAddressFinder: f)',
        ].join('\n')),
        isEmpty);
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
