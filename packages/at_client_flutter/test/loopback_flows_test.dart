import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loopback_flows.dart';

/// A [StateError] naming root.atsign.org's atDirectory.
final _refusal = throwsA(
  isA<StateError>().having(
    (e) => e.message,
    'message',
    contains('root.atsign.org:64'),
  ),
);

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
      _refusal,
      reason: 'open refuses root.atsign.org',
    );
    expect(
      (await loopbackPreference()).rootDomain,
      InternetAddress.loopbackIPv4.address,
      reason: 'the control: loopbackPreference names a loopback atDirectory',
    );
  });

  test('activate refuses an atDirectory off the loopback interface', () async {
    await expectLater(
      const LoopbackFlows().activate(
        '@alice',
        cramSecret: 'secret',
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(),
      ),
      _refusal,
      reason: 'activate refuses root.atsign.org',
    );
  });

  test('resumeEnrollment refuses an atDirectory off the loopback '
      'interface', () async {
    await expectLater(
      const LoopbackFlows().resumeEnrollment(
        '@alice',
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(),
      ),
      _refusal,
      reason: 'resumeEnrollment refuses root.atsign.org',
    );
  });

  test('enroll refuses an atDirectory off the loopback interface', () async {
    await expectLater(
      const LoopbackFlows().enroll(
        '@alice',
        otp: 'ABC123',
        app: 'app',
        device: 'device',
        namespaces: const {'app': 'rw'},
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(),
      ),
      _refusal,
      reason: 'enroll refuses root.atsign.org',
    );
  });
}
