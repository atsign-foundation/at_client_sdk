import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _sources() => Directory('lib/src/passkey')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

final _extendsAtException = RegExp(r'^\s*extends\s+AtException\b');

String _all() => _sources().map((f) => f.readAsStringSync()).join('\n');

/// The member of [source] whose declaration starts with [signature], through
/// its matching closing brace.
String _member(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) throw StateError('no $signature');
  var depth = 0;
  for (var i = source.indexOf('{', start); i < source.length; i++) {
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
      for (final m in found) {
        expect(m.group(2), matches(_extendsAtException),
            reason: '${m.group(1)} must extend AtException');
        expect(m.group(2), isNot(contains('implements Exception')));
      }
    });
  });

  group('flow surface', () {
    test(
        'the flow revokes only the other enrollments, while onboarding, and '
        'offers no revoke', () {
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
              'Future<_Written> _activateAndWrite('),
          contains('.revokeOtherEnrollments()'));
    });

    test('the flow offers no document or pointer delete', () {
      final all = _all();
      expect(all, isNot(contains('Future<void> delete(')));
      expect(all, isNot(contains("'delete:")));
    });
  });

  group('passkey library', () {
    final passkey = File('lib/passkey.dart');
    final exported = passkey.existsSync() ? passkey.readAsStringSync() : '';

    test('package:at_client/passkey.dart exports the passkey surface', () {
      for (final name in [
        'enrollment_gateway.dart',
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
