import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _sources() => Directory('lib/src/passkey')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

final _extendsAtException = RegExp(r'^\s*extends\s+AtException\b');

String _all() => _sources().map((f) => f.readAsStringSync()).join('\n');

/// Each construction of a delete verb builder, however it is formatted.
final _deleteBuilder = RegExp(r'\bDeleteVerbBuilder\s*\(');

/// The opening brace of a member's body, after its parameter list's closing
/// parenthesis and any `async`.
final _bodyStart = RegExp(r'\)\s*(?:async\s*)?\{');

/// [source] without its comment lines.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// The member of [source] whose declaration starts with [signature], through
/// its body's matching closing brace.
String _member(String source, Pattern signature) {
  final start = source.indexOf(signature);
  if (start < 0) throw StateError('no $signature');
  final body = _bodyStart.firstMatch(source.substring(start));
  if (body == null) throw StateError('$signature has no body');
  var depth = 0;
  for (var i = start + body.end - 1; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(start, i + 1);
  }
  throw StateError('$signature never closes');
}

void main() {
  group('sources', () {
    test('no analyzer suppression of visible-for-testing members', () {
      for (final f in _sources()) {
        expect(f.readAsStringSync(),
            isNot(contains('invalid_use_of_visible_for_testing_member')),
            reason: f.path);
      }
    });

    test(
        'the lifecycle helpers passkey code calls suppress the '
        'visible-for-testing lint once each', () {
      for (final path in [
        'lib/src/lifecycle/atsign_lifecycle.dart',
        'lib/src/lifecycle/pending_enrollment.dart',
      ]) {
        expect(
            'invalid_use_of_visible_for_testing_member'
                .allMatches(File(path).readAsStringSync()),
            hasLength(1),
            reason: path);
      }
    });

    test('no import reaches into another package src', () {
      final other = RegExp(r"import\s+'package:(?!at_client/)[^/']+/src/");
      for (final f in _sources()) {
        expect(other.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('no abstract interface class', () {
      expect(_all(), isNot(contains('abstract interface class')));
    });

    test('no exception implements Exception', () {
      expect(_all(), isNot(contains('implements Exception')));
    });

    test('every passkey exception extends AtException', () {
      final decl = RegExp(r'class\s+(\w+(?:Exception|Error))\b([^{]*)\{');
      final found = decl.allMatches(_all()).toList();
      expect(found, isNotEmpty);
      final heads = {for (final m in found) m.group(1)!: m.group(2)!};
      for (final m in found) {
        var root = m.group(1)!;
        for (final seen = {root};;) {
          final parent =
              RegExp(r'^\s*extends\s+(\w+)').firstMatch(heads[root]!)?.group(1);
          if (parent == null || !heads.containsKey(parent)) break;
          if (!seen.add(parent)) break;
          root = parent;
        }
        expect(heads[root], matches(_extendsAtException),
            reason: '${m.group(1)} must extend AtException');
        expect(m.group(2), isNot(contains('implements Exception')));
      }
    });
  });

  group('flow surface', () {
    test(
        'the flow revokes only the other enrollments, while completing an '
        'activation, and offers no revoke', () {
      final all = _all();
      expect(all.toLowerCase(), isNot(contains('revoke(')));
      expect('EnrollOperationEnum.revoke'.allMatches(all), hasLength(1));
      expect(
          _member(
              File('lib/src/passkey/enrollment_gateway.dart')
                  .readAsStringSync(),
              'Future<void> revokeOtherEnrollments()'),
          contains('EnrollOperationEnum.revoke'));
      expect('.revokeOtherEnrollments()'.allMatches(all), hasLength(1));
      expect(
          _member(
              File('lib/src/passkey/passkey_custody.dart').readAsStringSync(),
              'Future<void> _completeActivation('),
          contains('.revokeOtherEnrollments()'));
    });

    test(
        'the code names a revoke only in the one revoke path, its declaration '
        'and its one call', () {
      var rest = _code(_all()).replaceAll('unrevoke', '');
      for (final allowed in [
        'Future<void> revokeOtherEnrollments();',
        'Future<void> revokeOtherEnrollments() async',
        '.revokeOtherEnrollments()',
        'EnrollOperationEnum.revoke',
        "'a revoke was refused",
        "after revoking them'",
        // The warning each revoke logs.
        "warning('revoking enrollment",
        // The refusal of a revoke (AT0031) that is left to the list.
        'e is AtEnrollmentRevokeException',
      ]) {
        expect(allowed.allMatches(rest), hasLength(1), reason: allowed);
        rest = rest.replaceAll(allowed, '');
      }
      expect(rest.toLowerCase(), isNot(contains('revok')),
          reason: 'a revoke command, a tear-off of revokeOtherEnrollments or '
              'any other revoke is a second revoke path');
    });

    test('the flow offers no document or pointer delete', () {
      final all = _all();
      expect(all, isNot(contains('Future<void> delete(')));
      expect(all, isNot(contains("'delete:")));
      final deletes = {
        for (final f in _sources())
          if (_deleteBuilder.allMatches(f.readAsStringSync()).length
              case final n when n > 0)
            f.path: n
      };
      expect(deletes, {'lib/src/passkey/completion_due_record.dart': 1},
          reason: 'the passkey sources build one delete, of the '
              'completion-due record');
      expect(
          _member(
              File('lib/src/passkey/completion_due_record.dart')
                  .readAsStringSync(),
              RegExp(r'Future<void>\s+clear\(\s*\)')),
          matches(_deleteBuilder));
    });
  });

  group('passkey library', () {
    final passkey = File('lib/passkey.dart');
    final exported = passkey.existsSync() ? passkey.readAsStringSync() : '';

    test('package:at_client/passkey.dart exports the passkey surface', () {
      for (final name in [
        'enrollment_gateway.dart',
        'completion_due_record.dart',
        'enrollment_document_store.dart',
        'enrollment_pointer_store.dart',
        'public_lookup.dart',
        'at_server_at_keys_io.dart',
        'passkey_custody.dart',
      ]) {
        expect(exported, contains('src/passkey/$name'));
      }
      expect(RegExp(r'export\s').hasMatch(exported), isTrue);
    });

    test('the passkey library does not export the wire-bound store classes',
        () {
      expect(exported, isNot(contains('RemoteEnrollment')));
    });

    test('at_client.dart does not export the passkey library', () {
      final main = File('lib/at_client.dart').readAsStringSync();
      expect(main, isNot(contains('passkey')));
    });
  });
}
