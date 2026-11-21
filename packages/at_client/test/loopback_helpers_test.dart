import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:test/test.dart';

import 'test_utils/transport.dart';

/// The shared helpers refuse an atDirectory off the loopback interface
/// before anything connects; at_client_cli's
/// `unit_tests_stay_on_loopback_test.dart` scans this tree for any way past
/// them.
void main() {
  test('the shared helpers refuse an atDirectory off the loopback interface',
      () {
    expect(
        () => atDirectoryOf(AtClientPreference()),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('root.atsign.org:64'))));
    expect(
        atDirectoryOf(AtClientPreference()
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = 1),
        isA<CacheableSecondaryAddressFinder>(),
        reason: 'the control: a loopback atDirectory is handed back');
  });

  test(
      'the shared lookups refuse a connection with no finder whose root is '
      'off the loopback interface', () async {
    expect(
        () => loopbackLookUps()(
            atSign: '@alice',
            rootDomain: AtRootDomain('root.atsign.org', 64),
            authenticator: null),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('root.atsign.org:64'))));
    final loopbackRoot = loopbackLookUps()(
        atSign: '@alice',
        rootDomain: AtRootDomain(InternetAddress.loopbackIPv4.address, 1),
        authenticator: null);
    await loopbackRoot.close();

    final given = defaultAtDirectory;
    final givenFinder = loopbackLookUps()(
        atSign: '@alice',
        rootDomain: AtRootDomain('root.atsign.org', 64),
        authenticator: null,
        secondaryAddressFinder: given);
    expect(givenFinder.secondaryAddressFinder, same(given),
        reason: 'the control: a finder given is used, whatever the root');
    await givenFinder.close();
  });

  group('Given the shared loopback helpers', () {
    test(
        'when a test takes the default atDirectory or preference, then each '
        'names port 1 on 127.0.0.1', () {
      expect(loopbackHosts, {'127.0.0.1', 'localhost', '::1'});
      expect(loopbackPreference().rootDomain, '127.0.0.1');
      expect(loopbackPreference().rootPort, 1);
      expect(() => defaultAtDirectory, returnsNormally,
          reason: 'the default atDirectory is built through the refusal');
    });
  });
}
