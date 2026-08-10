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

// The conveyance surface is deliberately marked @experimental and will be
// reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
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

    when(
      () => mockKeychainStorage.validateEnrollment(atSign),
    ).thenAnswer((_) async => true);
    when(
      () => mockKeychainStorage.deleteEnrollmentData(atSign),
    ).thenAnswer((_) async {});
    when(
      () => mockAtClient.enrollmentService,
    ).thenReturn(mockEnrollmentService);
    when(() => mockAtLookUp.close()).thenAnswer((_) async {});
    when(
      () => mockKeychainAtKeysIo.write(any(), any()),
    ).thenAnswer((_) async {});

    service = FlutterEnrollmentService()
      ..atClientOverride = mockAtClient
      ..keychainStorage = mockKeychainStorage
      ..keychainAtKeysIo = mockKeychainAtKeysIo;
  });

  test(
    'an approval with no returned key material is reported approved',
    () async {
      // What at_client's approve() actually returns: id and status, no keys.
      when(() => mockEnrollmentService.approve(any())).thenAnswer(
        (_) async =>
            AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
      );

      final decision = EnrollmentRequestDecision.approved(
        enrollmentId: enrollmentId,
        apkamSymmetricKey: AtBytes.fromString('QUJD'),
        atSign: atSign,
      );

      final response = await service.approve(decision, mockAtLookUp);

      expect(response.enrollStatus, EnrollmentStatus.approved);
      expect(response.enrollmentId, enrollmentId);
      // Nothing to write: the approver holds no enrollee key material.
      verifyNever(() => mockKeychainAtKeysIo.write(any(), any()));
      verify(() => mockKeychainStorage.deleteEnrollmentData(atSign)).called(1);
      verify(() => mockAtLookUp.close()).called(1);
    },
  );

  test(
    'a conveyance refusal is not re-reported as a failed approval',
    () async {
      // What at_client's approve() throws when the server-side approval
      // succeeded but the enrollee's advertised key package was refused: the
      // enrollment is live and cannot decrypt, and the response rides along.
      final refusal = EnrollmentConveyanceException(
        'Enrollment $enrollmentId is approved, but the key package it '
        'advertised does not verify against its _apsk, so no secrets were '
        'shared with it and it will be unable to decrypt anything. Revoke it '
        'unless this is understood.',
        response: AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
        keyPackageStatus: KeyPackageStatus.rejected,
      );
      when(() => mockEnrollmentService.approve(any())).thenThrow(refusal);

      final decision = EnrollmentRequestDecision.approved(
        enrollmentId: enrollmentId,
        apkamSymmetricKey: AtBytes.fromString('QUJD'),
        atSign: atSign,
      );

      await expectLater(
        service.approve(decision, mockAtLookUp),
        throwsA(same(refusal)),
        reason:
            'wrapping this in "Enrollment failed" would report a '
            'server-side success as a failure — the caller must see the true '
            'state: approved, cannot decrypt, consider revoking',
      );

      // The approval itself succeeded, so the approval bookkeeping still runs.
      verify(() => mockKeychainStorage.deleteEnrollmentData(atSign)).called(1);
      verify(() => mockAtLookUp.close()).called(1);
    },
  );

  test('the pending record is dropped before approve() returns', () async {
    // Ordering, not the call itself: an unawaited delete is still *recorded*
    // by the mock, so verify() alone cannot tell the two apart.
    var dropped = false;
    when(() => mockKeychainStorage.deleteEnrollmentData(atSign)).thenAnswer((
      _,
    ) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      dropped = true;
    });
    when(() => mockEnrollmentService.approve(any())).thenAnswer(
      (_) async =>
          AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
    );

    final decision = EnrollmentRequestDecision.approved(
      enrollmentId: enrollmentId,
      apkamSymmetricKey: AtBytes.fromString('QUJD'),
      atSign: atSign,
    );

    await service.approve(decision, mockAtLookUp);

    expect(
      dropped,
      isTrue,
      reason:
          'left unawaited, the delete outlives the call that started it — so '
          'a failure in it has no caller left to catch it and surfaces as an '
          'unhandled async error',
    );
  });

  test('a keychain failure after approval is not a failed approval', () async {
    // The atServer has already recorded the decision by this point. Losing
    // the local pending row costs a stale row, not an enrollment.
    when(
      () => mockKeychainStorage.deleteEnrollmentData(atSign),
    ).thenThrow(Exception('keychain unavailable'));
    when(() => mockEnrollmentService.approve(any())).thenAnswer(
      (_) async =>
          AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved),
    );

    final decision = EnrollmentRequestDecision.approved(
      enrollmentId: enrollmentId,
      apkamSymmetricKey: AtBytes.fromString('QUJD'),
      atSign: atSign,
    );

    final response = await service.approve(decision, mockAtLookUp);

    expect(response.enrollStatus, EnrollmentStatus.approved);
    verify(() => mockAtLookUp.close()).called(1);
  });

  test('a refused approval still closes the connection', () async {
    when(
      () => mockEnrollmentService.approve(any()),
    ).thenThrow(Exception('the atServer refused the approval'));

    final decision = EnrollmentRequestDecision.approved(
      enrollmentId: enrollmentId,
      apkamSymmetricKey: AtBytes.fromString('QUJD'),
      atSign: atSign,
    );

    await expectLater(
      service.approve(decision, mockAtLookUp),
      throwsA(isA<Exception>()),
    );

    verify(() => mockAtLookUp.close()).called(1);
  });

  test('a failed denial still closes the connection', () async {
    // The mock answers nothing, so the real deny() fails partway through —
    // which is the point: the connection is the caller's either way.
    final decision = EnrollmentRequestDecision.denied(enrollmentId, atSign);

    await expectLater(
      service.deny(decision, mockAtLookUp),
      throwsA(isA<Exception>()),
    );

    verify(() => mockAtLookUp.close()).called(1);
  });

  test('a failed revocation still closes the connection', () async {
    final decision = EnrollmentRequestDecision.revoked(enrollmentId, atSign);

    await expectLater(
      service.revoke(decision, mockAtLookUp),
      throwsA(isA<Exception>()),
    );

    verify(() => mockAtLookUp.close()).called(1);
  });
}
