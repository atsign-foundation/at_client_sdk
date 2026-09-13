import 'package:at_auth/at_auth.dart'
    show AtEnrollment, EnrollmentRequestDecision;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// FROZEN: the commands `EnrollmentServiceImpl` sends to deny and revoke an
/// enrollment, on the client's own connection.
///
/// Raw literals on purpose: these are what the atServer parses, so a change
/// to one is a deliberate edit here, and that edit is the review.
void main() {
  const atSign = '@alice🛠';
  late MockAtClient client;
  late MockRemoteSecondary remote;
  late List<String> sent;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    client = MockAtClient();
    remote = MockRemoteSecondary();
    sent = [];
    when(() => client.getCurrentAtSign()).thenReturn(atSign);
    when(() => client.getRemoteSecondary()).thenReturn(remote);
  });

  /// Answers every verb with [response], recording the command each built.
  void answering(String response) {
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      sent.add(
          (invocation.positionalArguments.first as VerbBuilder).buildCommand());
      return response;
    });
  }

  EnrollmentServiceImpl service() =>
      EnrollmentServiceImpl(client, AtEnrollment.create());

  test('enroll:deny is the builder form', () async {
    answering('data:{"status":"denied","enrollmentId":"id-1"}');

    final response =
        await service().deny(EnrollmentRequestDecision.denied('id-1', atSign));

    expect(sent.single, 'enroll:deny:{"enrollmentId":"id-1"}\n');
    expect((response.enrollmentId, response.enrollStatus),
        ('id-1', EnrollmentStatus.denied));
  });

  test('enroll:revoke is the builder form', () async {
    answering('data:{"status":"revoked","enrollmentId":"id-1"}');

    final response = await service()
        .revoke(EnrollmentRequestDecision.revoked('id-1', atSign));

    expect(sent.single, 'enroll:revoke:{"enrollmentId":"id-1"}\n');
    expect(response.enrollStatus, EnrollmentStatus.revoked);
  });

  test('a forced revoke says so before the json', () async {
    answering('data:{"status":"revoked","enrollmentId":"id-1"}');

    await service()
        .revoke(EnrollmentRequestDecision.revoked('id-1', atSign, force: true));

    expect(sent.single, 'enroll:revoke:force:{"enrollmentId":"id-1"}\n');
  });

  test('anything but data: is the atServer\'s refusal, thrown', () async {
    answering('error:AT0025-Exception: enrollment id-1 is expired');

    await expectLater(
        () => service().deny(EnrollmentRequestDecision.denied('id-1', atSign)),
        throwsA(isA<AtEnrollmentException>().having((e) => e.message, 'message',
            allOf(contains('enroll:deny'), contains('AT0025')))));
  });
}
