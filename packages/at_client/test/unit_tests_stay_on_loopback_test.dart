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

final _finderConstruction =
    RegExp(r'CacheableSecondaryAddressFinder\(\s*([^,)]+)');

/// Each atDirectory finder built in [source], with the host argument it
/// names, and whether that is on the loopback interface.
Iterable<({String host, bool loopback})> findersIn(String source) =>
    _finderConstruction.allMatches(source).map((m) {
      final host = m.group(1)!.trim();
      return (host: host, loopback: _loopbackArguments.contains(host));
    });

/// No unit test names an atDirectory off the loopback interface: the shared
/// helpers refuse one before anything connects, and every finder a test
/// builds for itself names a loopback host.
void main() {
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

  test('every atDirectory finder a test builds names a loopback host', () {
    final self = File('test/unit_tests_stay_on_loopback_test.dart').absolute;
    final helper = File('test/test_utils/transport.dart').absolute;
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dart') &&
            // NOTE: samples are run by hand against the environment they
            // name, never by dart test.
            !f.path.contains('${Platform.pathSeparator}samples'
                '${Platform.pathSeparator}') &&
            f.absolute.path != self.path &&
            f.absolute.path != helper.path)
        .toList();
    expect(files.length, greaterThan(100),
        reason: 'the scan reads the test tree: ${files.length} files');
    expect(
        findersIn("CacheableSecondaryAddressFinder('root.atsign.org', 64)")
            .single
            .loopback,
        isFalse,
        reason: 'the control: a finder for the default root is caught');

    final loopback = <String>[];
    final offenders = <String>[];
    for (final file in files) {
      for (final finder in findersIn(file.readAsStringSync())) {
        (finder.loopback ? loopback : offenders)
            .add('${file.path}: ${finder.host}');
      }
    }
    expect(loopback, isNotEmpty,
        reason: 'the control: the scan finds the loopback finders tests '
            'build: $loopback');
    expect(offenders, isEmpty);
  });
}
