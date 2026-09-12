import 'dart:convert';

import 'package:at_auth/at_auth.dart' show EnrollmentRequestDecision;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/response.dart' show AtResponse;
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeListParams extends Fake implements EnrollmentListRequestParam {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

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
    registerFallbackValue(_FakeVerbBuilder());
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
    expect(passcode.expiry!.difference(DateTime.now()).inMinutes, 4,
        reason: 'five minutes from now, less the moment it took');
  });

  test('otp() with no expiry sends the bare verb, and the expiry is unknown',
      () async {
    when(() => remote.executeCommand('otp:get\n', auth: true))
        .thenAnswer((_) async => 'data:XYZ789');

    final passcode = await client.enrollments.otp(expiry: null);

    expect(passcode.value, 'XYZ789');
    expect(passcode.expiry, isNull,
        reason:
            'the atServer\'s default applies, and the client cannot see it');
    expect(passcode.isExpired, isFalse);
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
    expect(passcode.expiry!.difference(DateTime.now()).inMinutes, 9);
    verify(() => client.setSPP('ABC123', expiry: const Duration(minutes: 10)))
        .called(1);
  });

  test('spp() with no expiry sets a passcode that stands until replaced',
      () async {
    when(() => client.setSPP('ABC123', expiry: null))
        .thenAnswer((_) async => AtResponse()..response = 'ok');

    final passcode = await client.enrollments.spp('ABC123');

    expect(passcode.expiry, isNull);
    verify(() => client.setSPP('ABC123', expiry: null)).called(1);
  });

  test(
      'fetch(), unrevoke() and delete() send the enroll verb, pinned, and '
      'read the record back', () async {
    // The verb is a wire contract with every atServer implementation.
    final sent = <String>[];
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final command =
          (invocation.positionalArguments.first as VerbBuilder).buildCommand();
      sent.add(command);
      if (command.startsWith('enroll:fetch:')) {
        return 'data:${jsonEncode({
              'appName': 'wavi',
              'deviceName': 'phone',
              'namespace': {'wavi': 'rw'},
              'status': 'revoked',
            })}';
      }
      return 'data:ok';
    });

    final record = await client.enrollments.fetch('e-9');
    await client.enrollments.unrevoke('e-9');
    await client.enrollments.delete('e-9');

    expect(record?.enrollmentId, 'e-9',
        reason: 'the record the atServer serves does not repeat its id');
    expect((record?.appName, record?.status), ('wavi', 'revoked'));
    expect(sent, [
      'enroll:fetch:{"enrollmentId":"e-9"}\n',
      'enroll:unrevoke:{"enrollmentId":"e-9"}\n',
      'enroll:delete:{"enrollmentId":"e-9"}\n',
    ]);
  });

  test('fetch() answers null for a record the atServer does not hold',
      () async {
    when(() => remote.executeVerb(any())).thenAnswer((_) async => 'data:null');

    expect(await client.enrollments.fetch('nope'), isNull);
  });

  test('a refused enroll verb is thrown, naming the verb', () async {
    when(() => remote.executeVerb(any()))
        .thenAnswer((_) async => 'error:AT0011:enrollment is approved');

    await expectLater(
        client.enrollments.delete('e-1'),
        throwsA(isA<AtEnrollmentException>().having((e) => e.message, 'message',
            contains('enroll:delete:{"enrollmentId":"e-1"}'))));
  });

  test('requests are the new-request notifications, as records', () async {
    final notifications = MockNotificationService();
    when(() => client.notificationService).thenReturn(notifications);
    // The subscription filter is a wire contract with every atServer
    // implementation: it is the key a new request is announced under.
    when(() => notifications.subscribe(
            regex: r'.*\.new\.enrollments\.__manage', shouldDecrypt: false))
        .thenAnswer((_) => Stream.value(AtNotification(
            'n-1',
            'e-7.new.enrollments.__manage$atSign',
            atSign,
            atSign,
            0,
            'key',
            false)
          ..value = jsonEncode({
            'appName': 'wavi',
            'deviceName': 'phone',
            'namespace': {'wavi': 'rw'},
          })));

    final request = await client.enrollments.requests.first;

    expect(request.enrollmentId, 'e-7');
    expect(request.appName, 'wavi');
    expect(request.enrollmentStatus, EnrollmentStatus.pending);
  });

  test('a client with no enrollment service says so', () async {
    when(() => client.enrollmentService).thenReturn(null);

    await expectLater(
        () => client.enrollments.pending(), throwsA(isA<StateError>()));
  });
}
