import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// `Enrollment` as an app reads it: the grants as typed permissions, the
/// status as the atServer's vocabulary, and a request built from the
/// notification that announces it.
void main() {
  test('namespacePermissions reads r and rw as what they grant', () {
    final enrollment = Enrollment()
      ..namespace = {'wavi': 'rw', 'buzz': 'r', '__manage': 'rw'};

    final byName = {
      for (final p in enrollment.namespacePermissions) p.namespace: p
    };
    expect(byName.keys, {'wavi', 'buzz', '__manage'});
    expect((byName['wavi']!.read, byName['wavi']!.write), (true, true));
    expect((byName['buzz']!.read, byName['buzz']!.write), (true, false));
    expect(Enrollment().namespacePermissions, isEmpty,
        reason: 'a record with no grants has no permissions, not a throw');
  });

  test('enrollmentStatus is the typed status, or null for a record without',
      () {
    expect((Enrollment()..status = 'approved').enrollmentStatus,
        EnrollmentStatus.approved);
    expect((Enrollment()..status = 'pending').enrollmentStatus,
        EnrollmentStatus.pending);
    expect(Enrollment().enrollmentStatus, isNull);
  });

  test('fromNotification takes the id from the key and the record from the '
      'value, pending when the record names no status', () {
    final notification = AtNotification(
        'n-1',
        'e-9.new.enrollments.__manage@alice',
        '@alice',
        '@alice',
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false)
      ..value = jsonEncode({
        'appName': 'wavi',
        'deviceName': 'phone',
        'namespace': {'wavi': 'rw'},
        'encryptedAPKAMSymmetricKey': 'd3JhcHBlZA==',
      });

    final request = Enrollment.fromNotification(notification);

    expect(request.enrollmentId, 'e-9');
    expect((request.appName, request.deviceName), ('wavi', 'phone'));
    expect(request.namespace, {'wavi': 'rw'});
    expect(request.encryptedAPKAMSymmetricKey, 'd3JhcHBlZA==');
    expect(request.enrollmentStatus, EnrollmentStatus.pending,
        reason: 'a request the atServer has just announced awaits a decision');
  });
}
