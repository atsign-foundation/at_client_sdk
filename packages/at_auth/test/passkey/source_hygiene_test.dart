import 'dart:io';

import 'package:test/test.dart';

/// Reads every .dart file under lib/src/passkey (tests run from the package
/// root).
Map<String, List<String>> _sources() => {
      for (final f in Directory('lib/src/passkey')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsLinesSync(),
    };

void main() {
  test('there are passkey sources to check', () {
    expect(_sources(), isNotEmpty);
  });

  test('no kek type, field or parameter exists in the passkey library', () {
    final hits = <String>[];
    _sources().forEach((path, lines) {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains("'at_auth/custody/kek/v1'")) continue;
        if (RegExp('kek', caseSensitive: false).hasMatch(line)) {
          hits.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    });
    expect(hits, isEmpty);
  });

  test('the library ships no RecordSealer or PasskeyKeyDeriver implementation',
      () {
    final hits = <String>[];
    _sources().forEach((path, lines) {
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(
                r'(implements|extends|with)\s+[^{]*\b(RecordSealer|PasskeyKeyDeriver)\b')
            .hasMatch(lines[i])) {
          hits.add('$path:${i + 1}');
        }
      }
    });
    expect(hits, isEmpty);
  });

  test('the library silences the visible-for-testing lint in three places', () {
    final hits = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final _ in 'invalid_use_of_visible_for_testing_member'
            .allMatches(f.readAsStringSync()))
          f.path
    ]..sort();
    expect(hits, [
      'lib/src/at_auth_impl.dart',
      'lib/src/enroll/enrollment_handshake.dart',
      'lib/src/enroll/enrollment_submitter.dart',
    ]);
  });

  test('no passkey source silences the visible-for-testing lint', () {
    final hits = <String>[];
    _sources().forEach((path, lines) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('invalid_use_of_visible_for_testing_member')) {
          hits.add('$path:${i + 1}');
        }
      }
    });
    expect(hits, isEmpty);
  });
}
