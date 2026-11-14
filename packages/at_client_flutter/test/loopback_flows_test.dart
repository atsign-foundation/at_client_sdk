import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loopback_flows.dart';

/// The verbs a test runs for real refuse an atDirectory off the loopback
/// interface before anything connects; at_client_cli's
/// `unit_tests_stay_on_loopback_test.dart` scans this tree for any way past
/// them.
void main() {
  test('the real verbs a test runs refuse an atDirectory off the loopback '
      'interface', () async {
    await expectLater(
      const LoopbackFlows().open(
        '@alice',
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('root.atsign.org:64'),
        ),
      ),
    );
    expect(
      (await loopbackPreference()).rootDomain,
      InternetAddress.loopbackIPv4.address,
      reason: 'the control: loopbackPreference names a loopback atDirectory',
    );
  });
}
