import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/enroll/pq_native_onboard.dart'
    show firstEnrollmentAppName, firstEnrollmentDeviceName;
import 'package:at_auth/src/auth/models/at_auth_requests.dart'
    show AtOnboardingRequest;
import 'package:test/test.dart';

/// What a client holding no enrollment asks its first one to be.
///
/// It has no predecessor enrollment to carry an app, device and grants over
/// from, so these are the values it invents instead.
void main() {
  group('the identity a client with no enrollment asks for', () {
    test('it names the first-enrollment app', () {
      expect(AtClientImpl.firstEnrollmentIdentity().appName,
          firstEnrollmentAppName,
          reason: 'this IS the atSign\'s first enrollment in everything but '
              'the path that creates it, so it should be nameable as such on '
              'a roster beside one created at onboarding');
    });

    test(
        'it asks for everything, because its connection already holds '
        'everything', () {
      expect(AtClientImpl.firstEnrollmentIdentity().grants,
          {'*': 'rw', '__manage': 'rw'},
          reason: 'the connection making the request has proved possession of '
              'the atSign\'s own root credential and is unscoped, so there is '
              'no narrower grant to bound it by and nothing is escalated. A '
              'scoped first enrollment could not even approve a second one');
    });

    test('the device name is NOT the bare constant', () {
      expect(AtClientImpl.firstEnrollmentIdentity().deviceName,
          isNot(firstEnrollmentDeviceName),
          reason: 'the bare constant collides across sibling clones of one '
              'keyfile, and the atServer refuses the second one');
      expect(AtClientImpl.firstEnrollmentIdentity().deviceName,
          startsWith('$firstEnrollmentDeviceName-'),
          reason: 'still recognisable on a roster as the first enrollment');
    });

    test('two clients of one keyfile ask for different device names', () {
      final names = {
        for (var i = 0; i < 8; i++)
          AtClientImpl.firstEnrollmentIdentity().deviceName
      };
      expect(names.length, 8,
          reason: 'each device retrofits to its own enrollment, so each must '
              'name itself differently or the atServer refuses all but the '
              'first');
    });
  });

  /// at_auth carries the same values as field defaults on its internal
  /// [AtOnboardingRequest], and a default is not a constant this package can
  /// reference, so nothing but this pins the two together.
  group('the first-enrollment constants match at_auth\'s own defaults', () {
    final request =
        AtOnboardingRequest('@alice', signingAlgoType: SigningAlgoType.rsa2048);

    test('appName', () {
      expect(firstEnrollmentAppName, request.appName);
    });

    test('deviceName', () {
      expect(firstEnrollmentDeviceName, request.deviceName);
    });
  });
}
