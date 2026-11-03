import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/register/onboarding_util.dart';
import 'package:test/test.dart';

/// A registrar that answers every request for a free atSign with an error.
class _RefusingRegistrar extends OnboardingUtil {
  _RefusingRegistrar() : super('app-key');

  @override
  Future<List<String>> getFreeAtSigns(
          {int amount = 1, String authority = ''}) async =>
      throw Exception('the registrar is down');
}

/// A registrar for an email that already owns atSigns: it refuses every code
/// but [_code], answers [_code] with 'follow-up', and gives the CRAM key once
/// that code is confirmed.
class _FollowUpRegistrar extends OnboardingUtil {
  static const _code = 'RIGHT';
  final List<String> _codesTyped;
  final List<String> confirmations = [];

  _FollowUpRegistrar(this._codesTyped) : super('app-key');

  @override
  String getVerificationCodeFromUser() => _codesTyped.removeAt(0);

  @override
  Future<String> validateOtp(String atSign, String email, String otp,
      {String confirmation = 'true', String authority = ''}) async {
    confirmations.add(confirmation);
    if (otp != _code) return 'retry';
    return confirmation == 'true' ? '@$atSign:the-cram-key' : 'follow-up';
  }
}

/// A registrar that answers 'follow-up' to every code, confirmed or not, for
/// its first three answers. After that it gives the CRAM key, so a flow that
/// keeps confirming finishes and fails the test instead of hanging it.
class _EndlessFollowUpRegistrar extends _FollowUpRegistrar {
  _EndlessFollowUpRegistrar() : super([_FollowUpRegistrar._code]);

  @override
  Future<String> validateOtp(String atSign, String email, String otp,
      {String confirmation = 'true', String authority = ''}) async {
    confirmations.add(confirmation);
    return confirmations.length <= 3 ? 'follow-up' : '@$atSign:the-cram-key';
  }
}

/// A registrar that answers a code with 'follow-up', refuses its confirmation
/// as expired, answers the next code typed with 'follow-up' too, and gives the
/// CRAM key once that code is confirmed. It answers in that order whatever
/// confirmation it is sent, so the test checks what the flow sends.
class _ExpiredConfirmationRegistrar extends _FollowUpRegistrar {
  static const _answers = ['follow-up', 'retry', 'follow-up'];

  _ExpiredConfirmationRegistrar()
      : super([_FollowUpRegistrar._code, _FollowUpRegistrar._code]);

  @override
  Future<String> validateOtp(String atSign, String email, String otp,
      {String confirmation = 'true', String authority = ''}) async {
    confirmations.add(confirmation);
    return confirmations.length <= _answers.length
        ? _answers[confirmations.length - 1]
        : '@$atSign:the-cram-key';
  }
}

void main() {
  test('A third code accepted with a follow-up gets the CRAM key', () async {
    final registrar = _FollowUpRegistrar(['WRONG1', 'WRONG2', 'RIGHT']);
    final params = {
      'authority': 'registrar.example',
      'atsign': 'alice123',
      'email': 'alice@example.com',
    };

    await RegistrationFlow(params, registrar).add(ValidateOtp()).start();

    expect(params['cramkey'], 'the-cram-key');
    expect(registrar.confirmations, ['false', 'false', 'false', 'true']);
  });

  test('A registrar asking twice to confirm a code ends the registration',
      () async {
    final registrar = _EndlessFollowUpRegistrar();
    final flow = RegistrationFlow({
      'authority': 'registrar.example',
      'atsign': 'alice123',
      'email': 'alice@example.com',
    }, registrar)
      ..add(ValidateOtp());

    await expectLater(
        flow.start(),
        throwsA(isA<AtClientException>().having(
            (e) => e.message, 'message', contains('asked again to confirm'))));
    expect(registrar.confirmations, ['false', 'true']);
  });

  test('A code typed after a refused confirmation is confirmed in its turn',
      () async {
    final registrar = _ExpiredConfirmationRegistrar();
    final params = {
      'authority': 'registrar.example',
      'atsign': 'alice123',
      'email': 'alice@example.com',
    };

    await RegistrationFlow(params, registrar).add(ValidateOtp()).start();

    expect(params['cramkey'], 'the-cram-key');
    expect(registrar.confirmations, ['false', 'true', 'false', 'true']);
  });

  test(
      'when the registrar refuses a step, then the flow throws an '
      'AtClientException, as the README tells a migrating caller to catch',
      () async {
    final flow = RegistrationFlow(
        {'authority': 'registrar.example'}, _RefusingRegistrar())
      ..add(GetFreeAtsign());

    await expectLater(flow.start(), throwsA(isA<AtClientException>()));
  });
}
