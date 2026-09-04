import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// The atServer refuses foreign writes on this match, so the spellings are
/// pinned as raw literals rather than derived from the constant under test.
void main() {
  final regex = RegExp(EnrollmentConstants.regexForPerEnrollmentNamespaces);

  // NOTE: the group name is a raw literal; the atServer reads it by name.
  String? idOf(String key) => regex.firstMatch(key)?.namedGroup('EnId');

  group('regexForPerEnrollmentNamespaces captures the enrollment id', () {
    test('after a dot, which is the ordinary shape', () {
      expect(idOf('secret.abc.a.__e@alice'), 'abc');
      expect(idOf('public:_apsk.abc.a.__e@alice'), 'abc');
      expect(idOf('public:_apsk.primary.a.__e@alice'), 'primary');
    });

    test('at the START of the key, where the name IS the namespace', () {
      // NOTE: a dot-only anchor missed these; the guard never saw them.
      expect(idOf('abc.a.__e@alice'), 'abc');
      expect(idOf('x.r.__e@alice'), 'x');
      expect(idOf('y.d.__e@alice'), 'y');
    });

    test('after a colon, in the shared and cached forms', () {
      expect(idOf('@bob:abc.a.__e@alice'), 'abc');
      expect(idOf('cached:@bob:x.r.__e@alice'), 'x');
    });

    test('and matches nothing that is not a per-enrollment key', () {
      expect(idOf('phone.wavi@alice'), isNull);
      expect(idOf('abc.a.__manage@alice'), isNull);
      expect(idOf('abc.b.__e@alice'), isNull,
          reason: 'only the approved, revoked and deleted namespaces exist');
    });
  });

  test('the named group the atServer reads is EnId', () {
    expect(
        RegExp(EnrollmentConstants.regexForPerEnrollmentNamespaces)
            .firstMatch('secret.abc.a.__e@alice')
            ?.namedGroup('EnId'),
        'abc');
  });
}
