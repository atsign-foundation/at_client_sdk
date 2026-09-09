import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'enrollment_teardown.dart' show isRootEnrollment;

Enrollment withNamespaces(Map<String, dynamic> ns) =>
    Enrollment()..namespace = ns;

void main() {
  test('the shape the atServer builds for the primary enrollment is a root',
      () {
    // Copied from at_server's EnrollmentManager, which constructs the primary
    // enrollment with exactly this map.
    expect(isRootEnrollment(withNamespaces({'*': 'rw', '__manage': 'rw'})),
        isTrue);
  });

  test('the shape this suite creates is not a root', () {
    expect(
        isRootEnrollment(withNamespaces({'e2etest': 'rw', '__config': 'rw'})),
        isFalse);
  });

  test('either half alone is not a root', () {
    expect(isRootEnrollment(withNamespaces({'*': 'rw'})), isFalse);
    expect(isRootEnrollment(withNamespaces({'__manage': 'rw'})), isFalse);
  });

  test('read-only on either half is not a root', () {
    expect(isRootEnrollment(withNamespaces({'*': 'r', '__manage': 'rw'})),
        isFalse);
    expect(isRootEnrollment(withNamespaces({'*': 'rw', '__manage': 'r'})),
        isFalse);
  });

  test('a null namespace map is not a root', () {
    expect(isRootEnrollment(Enrollment()), isFalse);
  });
}
