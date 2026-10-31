import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/register/onboarding_util.dart';
import 'package:test/test.dart';

/// A registrar that answers every request for a free atSign with an error.
class _RefusingRegistrar extends OnboardingUtil {
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

  _FollowUpRegistrar(this._codesTyped);

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

void main() {
  test(
      'when the last verification code allowed is accepted with a follow-up, '
      'then the flow confirms it and gets the CRAM key', () async {
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
