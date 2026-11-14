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
}
