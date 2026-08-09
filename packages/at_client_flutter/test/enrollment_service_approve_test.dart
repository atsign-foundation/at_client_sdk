/// A successful approval must be reported as a success.
///
/// at_client's `approve()` returns `(enrollmentId, status)` with no
/// `atAuthKeys` — the enrollee files its own keys on its own device, so there
/// is nothing for the approver to hold. An approver-side null-bang on
/// `atAuthKeys` therefore fires on every approval, and the generic catch
/// around it re-reports the success as `Enrollment failed: Null check
/// operator used on a null value` — after the server-side approval has
/// already gone through.
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtClient extends Mock implements AtClient {}

class MockEnrollmentService extends Mock implements EnrollmentService {}

class MockKeychainStorage extends Mock implements KeychainStorage {}

class MockKeychainAtKeysIo extends Mock implements KeychainAtKeysIo {}

class MockAtLookUp extends Mock implements AtLookUp {}

class FakeEnrollmentRequestDecision extends Fake
    implements EnrollmentRequestDecision {}

class FakeAtKeys extends Fake implements AtKeys {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const atSign = '@alice';
  const enrollmentId = 'approve-eid-1';

  late MockAtClient mockAtClient;
  late MockEnrollmentService mockEnrollmentService;
  late MockKeychainStorage mockKeychainStorage;
  late MockKeychainAtKeysIo mockKeychainAtKeysIo;
  late MockAtLookUp mockAtLookUp;
  late FlutterEnrollmentService service;

  setUpAll(() {
    registerFallbackValue(FakeEnrollmentRequestDecision());
    registerFallbackValue(FakeAtKeys());
  });

  setUp(() {
    mockAtClient = MockAtClient();
    mockEnrollmentService = MockEnrollmentService();
    mockKeychainStorage = MockKeychainStorage();
    mockKeychainAtKeysIo = MockKeychainAtKeysIo();
    mockAtLookUp = MockAtLookUp();

    when(() => mockKeychainStorage.validateEnrollment(atSign))
        .thenAnswer((_) async => true);
    when(() => mockKeychainStorage.deleteEnrollmentData(atSign))
        .thenAnswer((_) async {});
    when(() => mockAtClient.enrollmentService)
        .thenReturn(mockEnrollmentService);
    when(() => mockAtLookUp.close()).thenAnswer((_) async {});
    when(() => mockKeychainAtKeysIo.write(any(), any()))
        .thenAnswer((_) async {});

    service = FlutterEnrollmentService()
      ..atClientOverride = mockAtClient
      ..keychainStorage = mockKeychainStorage
      ..keychainAtKeysIo = mockKeychainAtKeysIo;
  });

  test('an approval with no returned key material is reported approved',
      () async {
    // What at_client's approve() actually returns: id and status, no keys.
    when(() => mockEnrollmentService.approve(any())).thenAnswer(
        (_) async => AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved));

    final decision = EnrollmentRequestDecision.approved(
        enrollmentId: enrollmentId,
        apkamSymmetricKey: AtBytes.fromString('QUJD'),
        atSign: atSign);

    final response = await service.approve(decision, mockAtLookUp);

    expect(response.enrollStatus, EnrollmentStatus.approved);
    expect(response.enrollmentId, enrollmentId);
    // Nothing to write: the approver holds no enrollee key material.
    verifyNever(() => mockKeychainAtKeysIo.write(any(), any()));
    verify(() => mockKeychainStorage.deleteEnrollmentData(atSign)).called(1);
    verify(() => mockAtLookUp.close()).called(1);
  });
}
