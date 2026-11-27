import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_client/connection_default_budget.feature
void main() {
  test('the default connection budget stays five seconds', () {
    expect(AtConnection.defaultBudget, const Duration(seconds: 5),
        reason: 'every attempt() and awaitOnline() caller that names no '
            'budget relies on the five second default; a session open passes '
            'the network default as its own');
  });
}
