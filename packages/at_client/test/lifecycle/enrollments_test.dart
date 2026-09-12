import 'package:at_auth/at_auth.dart' show EnrollmentRequestDecision;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/response.dart' show AtResponse;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeListParams extends Fake implements EnrollmentListRequestParam {}

class _FakeDecision extends Fake implements EnrollmentRequestDecision {}

/// `client.enrollments`: the approving side, as a facade over the client's
/// enrollment service and its passcode verbs. What each verb hands the
/// service, and the two passcode commands as raw literals, are what is
/// pinned here; the service's own behaviour has its own tests.
void main() {
  const atSign = '@manager';
  late MockAtClient client;
  late MockEnrollmentService service;
  late MockRemoteSecondary remote;

  Enrollment record(String id, {String status = 'pending', String? wrapped}) =>
      Enrollment()
        ..enrollmentId = id
        ..appName = 'wavi'
        ..deviceName = 'phone'
        ..status = status
        ..namespace = {'wavi': 'rw'}
        ..encryptedAPKAMSymmetricKey = wrapped;

  setUpAll(() {
    registerFallbackValue(_FakeListParams());
    registerFallbackValue(_FakeDecision());
  });

  setUp(() {
    client = MockAtClient();
    service = MockEnrollmentService();
    remote = MockRemoteSecondary();
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.enrollmentService).thenReturn(service);
    when(() => client.getRemoteSecondary()).thenReturn(remote);
  });

  EnrollmentListRequestParam paramsPassed() =>
      verify(() => service.fetchEnrollmentRequests(
              enrollmentListParams: captureAny(named: 'enrollmentListParams')))
          .captured
          .single as EnrollmentListRequestParam;

  test('pending() asks the service for the pending requests', () async {
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [record('e-1')]);

    final pending = await client.enrollments.pending();

    expect(pending.map((e) => e.enrollmentId), ['e-1']);
    expect(paramsPassed().enrollmentListFilter, [EnrollmentStatus.pending]);
  });

  test('list() passes the app and device filters through', () async {
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => []);

    await client.enrollments.list(
        statuses: [EnrollmentStatus.approved], app: 'wavi', device: 'phone');

    final params = paramsPassed();
    expect(params.enrollmentListFilter, [EnrollmentStatus.approved]);
    expect((params.appName, params.deviceName), ('wavi', 'phone'));
  });

  test('approve() decides the request the roster holds, wrapped key and all',
      () async {
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [record('e-1', wrapped: 'd3JhcHBlZA==')]);
    when(() => service.approve(any())).thenAnswer(
        (_) async => throw UnimplementedError('the response is not read'));

    await expectLater(
        client.enrollments.approve('e-1'), throwsA(isA<UnimplementedError>()),
        reason: 'the rig: the stub proves approve() reached the service, and '
            'the facade hands the response to nobody');
    final decision = verify(() => service.approve(captureAny())).captured.single
        as EnrollmentRequestDecision;
    expect(decision.enrollmentId, 'e-1');
    expect(decision.atSign, atSign);
    expect(decision.encryptedAPKAMSymmetricKey, 'd3JhcHBlZA==',
        reason: 'the wrapped key the enrollee sent rides the decision, which '
            'is what the approver unwraps');
  });

  test(
      'approve() hands an empty wrapped key through, which asks the service '
      'to mint one', () async {
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [record('e-2')]);
    when(() => service.approve(any())).thenAnswer(
        (_) async => throw UnimplementedError('the response is not read'));

    await expectLater(
        client.enrollments.approve('e-2'), throwsA(isA<UnimplementedError>()));
    final decision = verify(() => service.approve(captureAny())).captured.single
        as EnrollmentRequestDecision;
    expect(decision.encryptedAPKAMSymmetricKey, isEmpty);
  });

  test('approve() refuses an id the roster does not hold', () async {
    when(() => service.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [record('e-1')]);

    await expectLater(client.enrollments.approve('nope'),
        throwsA(isA<AtEnrollmentException>()));
    verifyNever(() => service.approve(any()));
  });

  test('deny() and revoke() build the decisions the service takes', () async {
    when(() => service.deny(any())).thenAnswer(
        (_) async => throw UnimplementedError('the response is not read'));
    when(() => service.revoke(any())).thenAnswer(
        (_) async => throw UnimplementedError('the response is not read'));

    await expectLater(
        client.enrollments.deny('e-1'), throwsA(isA<UnimplementedError>()));
    final denied = verify(() => service.deny(captureAny())).captured.single
        as EnrollmentRequestDecision;
    expect((denied.enrollmentId, denied.atSign), ('e-1', atSign));
    expect(denied.enrollOperationEnum, EnrollOperationEnum.deny);

    await expectLater(client.enrollments.revoke('e-3', force: true),
        throwsA(isA<UnimplementedError>()));
    final revoked = verify(() => service.revoke(captureAny())).captured.single
        as EnrollmentRequestDecision;
    expect(revoked.enrollmentId, 'e-3');
    expect(revoked.enrollOperationEnum, EnrollOperationEnum.revoke);
    expect(revoked.force, isTrue);
  });

  test(
      'otp() sends the passcode verb with its ttl, pinned, and reads the '
      'passcode back', () async {
    // The verb is a wire contract with every atServer implementation.
    when(() => remote.executeCommand('otp:get:ttl:300000\n', auth: true))
        .thenAnswer((_) async => 'data:ABC123');

    final passcode = await client.enrollments.otp();

    expect(passcode.value, 'ABC123');
    expect(passcode.isExpired, isFalse);
    expect(passcode.expiry.difference(DateTime.now()).inMinutes, 4,
        reason: 'five minutes from now, less the moment it took');
  });

  test('otp() refuses an atServer that issued nothing', () async {
    when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async => 'error:AT0009:not authorised');

    await expectLater(
        client.enrollments.otp(), throwsA(isA<AtEnrollmentException>()));
  });

  test(
      'spp() sets the passcode through the client and hands it back with '
      'its expiry', () async {
    when(() => client.setSPP('ABC123', expiry: const Duration(minutes: 10)))
        .thenAnswer((_) async => AtResponse()..response = 'ok');

    final passcode = await client.enrollments
        .spp('ABC123', expiry: const Duration(minutes: 10));

    expect(passcode.value, 'ABC123');
    expect(passcode.expiry.difference(DateTime.now()).inMinutes, 9);
    verify(() => client.setSPP('ABC123', expiry: const Duration(minutes: 10)))
        .called(1);
  });

  test('a client with no enrollment service says so', () async {
    when(() => client.enrollmentService).thenReturn(null);

    await expectLater(
        () => client.enrollments.pending(), throwsA(isA<StateError>()));
  });
}
