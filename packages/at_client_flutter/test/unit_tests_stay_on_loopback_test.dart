import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loopback_flows.dart';

/// The arguments naming an atDirectory host that a test may build a finder
/// with.
const _loopbackArguments = {
  "'127.0.0.1'",
  '"127.0.0.1"',
  "'localhost'",
  'InternetAddress.loopbackIPv4.address',
};

/// The dialogs that run the lifecycle verbs, through `flows`.
const _dialogs = ['PkamDialog', 'CramDialog', 'ApkamActivationDialog'];

/// What in [source] could reach an atDirectory off the loopback interface:
/// the real verbs built without [LoopbackFlows], a dialog built without its
/// `flows`, and a finder built for a host that is not a loopback one.
List<String> offTheLoopbackIn(String source) {
  final found = <String>[];
  for (final m in RegExp(r'\bAtsignFlows\(\)').allMatches(source)) {
    found.add('the real verbs at offset ${m.start}');
  }
  for (final dialog in _dialogs) {
    for (final m in RegExp('\\b$dialog(\\.show)?\\(').allMatches(source)) {
      if (m.group(1) != null) {
        found.add('$dialog.show at offset ${m.start}');
        continue;
      }
      if (!_argumentsAt(source, m.end).contains('flows:')) {
        found.add('$dialog with no flows at offset ${m.start}');
      }
    }
  }
  for (final m in RegExp(
    r'CacheableSecondaryAddressFinder\(\s*([^,)]+)',
  ).allMatches(source)) {
    final host = m.group(1)!.trim();
    if (!_loopbackArguments.contains(host)) found.add('a finder for $host');
  }
  return found;
}

/// The text of the argument list that opens just before [start] in
/// [source], up to its closing parenthesis.
String _argumentsAt(String source, int start) {
  var depth = 1;
  for (var i = start; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return source.substring(start, i);
  }
  return source.substring(start);
}

/// No unit test names an atDirectory off the loopback interface: the verbs
/// a test runs for real refuse one before anything connects, and nothing in
/// a test reaches them another way.
void main() {
  test('the real verbs a test runs refuse an atDirectory off the loopback '
      'interface', () async {
    await expectLater(
      const LoopbackFlows().open(
        '@alice',
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('root.atsign.org:64'),
        ),
      ),
    );
    expect(
      (await loopbackPreference()).rootDomain,
      InternetAddress.loopbackIPv4.address,
      reason: 'the control: loopbackPreference names a loopback atDirectory',
    );
  });

  test('nothing in a test reaches the verbs without LoopbackFlows', () {
    final self = File('test/unit_tests_stay_on_loopback_test.dart').absolute;
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && f.absolute.path != self.path)
        .toList();
    expect(
      files.length,
      greaterThan(10),
      reason: 'the scan reads the test tree: ${files.length} files',
    );
    expect(
      offTheLoopbackIn(
        "const AtsignFlows(); PkamDialog(atSign: a, keys: k, preference: p); "
        "CacheableSecondaryAddressFinder('root.atsign.org', 64)",
      ),
      hasLength(3),
      reason: 'the control: each way past LoopbackFlows is caught',
    );
    expect(
      offTheLoopbackIn('PkamDialog(atSign: a, keys: k, flows: f(x))'),
      isEmpty,
      reason: 'the control: a dialog given its flows passes',
    );

    final offenders = <String>[
      for (final file in files)
        for (final found in offTheLoopbackIn(file.readAsStringSync()))
          '${file.path}: $found',
    ];
    expect(offenders, isEmpty);
  });
}
