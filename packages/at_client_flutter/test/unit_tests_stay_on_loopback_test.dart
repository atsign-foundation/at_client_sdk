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

/// What in [source], the text of the file at [path], could make a test reach
/// an atDirectory off the loopback interface: the real verbs without
/// [LoopbackFlows], through `AtsignFlows` itself or a subclass of it; a
/// dialog built without its own `flows`; a finder built for another host, or
/// by a tear-off or a subclass; and a connection factory invoked with no
/// finder.
List<String> offTheLoopbackIn(String source, {String path = ''}) {
  final found = <String>[];
  for (final m in RegExp(r'\bAtsignFlows\(\)').allMatches(source)) {
    found.add('the real verbs at offset ${m.start}');
  }
  if (!path.endsWith('loopback_flows.dart')) {
    for (final m in RegExp(r'extends\s+AtsignFlows\b').allMatches(source)) {
      found.add('a subclass of AtsignFlows at offset ${m.start}');
    }
  }
  for (final m in RegExp(
    r'class\s+\w+\s+(?:extends\s+(\w+)\s+)?implements\s+AtsignFlows\b',
  ).allMatches(source)) {
    if (m.group(1) != 'Mock') {
      found.add('AtsignFlows implemented at offset ${m.start}');
    }
  }
  for (final dialog in _dialogs) {
    for (final m in RegExp('\\b$dialog(\\.show)?\\(').allMatches(source)) {
      if (m.group(1) != null) {
        found.add('$dialog.show at offset ${m.start}');
        continue;
      }
      final names = topLevel(argumentsAt(source, m.end));
      if (!RegExp(r'(^|[,\s])flows\s*:').hasMatch(names)) {
        found.add('$dialog with no flows at offset ${m.start}');
      }
    }
  }
  for (final m in RegExp(
    r'\b(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\s*\(\s*([^,)]+)',
  ).allMatches(source)) {
    final host = m.group(2)!.trim();
    if (!_loopbackArguments.contains(host)) {
      found.add('a ${m.group(1)} for $host');
    }
  }
  for (final m in RegExp(
    r'\b(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\.new\b|'
    r'extends\s+(CacheableSecondaryAddressFinder|SecondaryUrlFinder)\b',
  ).allMatches(source)) {
    found.add('a finder torn off or subclassed at offset ${m.start}');
  }
  for (final m in RegExp(
    r'\b(secureSocketLookUps|proxyLookUps)\s*\(',
  ).allMatches(source)) {
    final factoryArguments = argumentsAt(source, m.end);
    final after = m.end + factoryArguments.length + 1;
    final rest = source.substring(after);
    if (rest.trimLeft().startsWith('(') &&
        !argumentsAt(
          source,
          after + rest.indexOf('(') + 1,
        ).contains('secondaryAddressFinder:')) {
      found.add('${m.group(1)} invoked with no finder');
    }
  }
  return found;
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

  test('the scan catches each way past LoopbackFlows, and passes the rest', () {
    expect(
      offTheLoopbackIn(
        [
          'const AtsignFlows();',
          'class _Real extends AtsignFlows { const _Real(); }',
          'class _Fake implements AtsignFlows {}',
          'PkamDialog(atSign: a, keys: k, preference: p);',
          'CramDialog(atSign: a, preference: f(flows: x));',
          'PkamDialog.show(context, atSign: a);',
          "CacheableSecondaryAddressFinder('root.atsign.org', 64)",
          'final f = SecondaryUrlFinder.new;',
          'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: '
              'null)',
        ].join('\n'),
      ),
      hasLength(9),
    );
    expect(
      offTheLoopbackIn(
        [
          'PkamDialog(atSign: a, keys: k, flows: f(x))',
          'class _Mock extends Mock implements AtsignFlows {}',
          "CacheableSecondaryAddressFinder('127.0.0.1', port)",
        ].join('\n'),
      ),
      isEmpty,
    );
  });

  test('the scan catches each spelling of each way on its own', () {
    for (final way in [
      'const AtsignFlows();',
      'class _Real extends AtsignFlows { const _Real(); }',
      'class _Fake implements AtsignFlows {}',
      'class _Fake extends Base implements AtsignFlows {}',
      for (final dialog in [
        'PkamDialog',
        'CramDialog',
        'ApkamActivationDialog',
      ]) ...[
        '$dialog(atSign: a, preference: p);',
        '$dialog.show(context, atSign: a, flows: f);',
      ],
      'CramDialog(atSign: a, preference: f(a, flows: x));',
      "CacheableSecondaryAddressFinder('example.com', 64)",
      "SecondaryUrlFinder('example.com', 64)",
      'final f = CacheableSecondaryAddressFinder.new;',
      'final f = SecondaryUrlFinder.new;',
      'class Mine extends CacheableSecondaryAddressFinder {}',
      'class Mine extends SecondaryUrlFinder {}',
      'secureSocketLookUps()(atSign: a, rootDomain: r, authenticator: null)',
      'proxyLookUps(root)(atSign: a, rootDomain: r, authenticator: null)',
    ]) {
      expect(offTheLoopbackIn(way), hasLength(1), reason: way);
    }
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

    final offenders = <String>[
      for (final file in files)
        for (final found in offTheLoopbackIn(
          file.readAsStringSync(),
          path: file.path,
        ))
          '${file.path}: $found',
    ];
    expect(offenders, isEmpty);
  });
}
