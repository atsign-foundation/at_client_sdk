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

void main() {
  test(
      'when the registrar refuses a step, then the flow throws an '
      'AtClientException, as the README tells a migrating caller to catch',
      () async {
    final flow = RegistrationFlow({'authority': 'registrar.example'},
        _RefusingRegistrar())
      ..add(GetFreeAtsign());

    await expectLater(flow.start(), throwsA(isA<AtClientException>()));
  });
}
