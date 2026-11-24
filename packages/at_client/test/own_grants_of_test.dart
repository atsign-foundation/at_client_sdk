import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class _MockAtClient extends Mock implements AtClient {}

/// Catalogue: features/at_client/own_grants_of.feature
///
/// Imports the function from the barrel only, as an outside caller must.
void main() {
  late _MockAtClient atClient;
  late MockEnrollmentService enrollmentService;

  setUp(() {
    atClient = _MockAtClient();
    enrollmentService = MockEnrollmentService();
    when(() => atClient.enrollmentService).thenReturn(enrollmentService);
  });

  void listing(List<Enrollment> enrollments) {
    when(() => enrollmentService.fetchEnrollmentRequests(
        enrollmentListParams: any(named: 'enrollmentListParams'))).thenAnswer(
      (_) async => enrollments,
    );
  }

  group('Given a client reading its own enrollment grants', () {
    test('A client with an approved enrollment reads its grants', () async {
      when(() => atClient.enrollmentId).thenReturn('mine');
      listing([
        Enrollment()
          ..enrollmentId = 'mine'
          ..namespace = {'buzz': 'rw', '__manage': 'rw', '*': 'r'},
        Enrollment()
          ..enrollmentId = 'other'
          ..namespace = {'secret': 'rw'},
      ]);

      expect(await ownGrantsOf(atClient),
          {'buzz': 'rw', '__manage': 'rw', '*': 'r'});
    });

    for (final id in <String?>[null, EnrollmentConstants.primaryEnrollmentId]) {
      test('The primary enrollment has no grants to read ($id)', () async {
        when(() => atClient.enrollmentId).thenReturn(id);

        expect(await ownGrantsOf(atClient), isNull);
        verifyNever(() => enrollmentService.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')));
      });
    }

    test('An enrollment the atServer does not list answers an empty map',
        () async {
      when(() => atClient.enrollmentId).thenReturn('mine');
      listing([
        Enrollment()
          ..enrollmentId = 'other'
          ..namespace = {'secret': 'rw'},
      ]);

      expect(await ownGrantsOf(atClient), isEmpty);
    });

    test('The function is nameable from the package library', () {
      expect(
          ownGrantsOf, isA<Future<Map<String, dynamic>?> Function(AtClient)>());
    });
  });
}
