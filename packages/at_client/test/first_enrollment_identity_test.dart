import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/enroll/pq_native_onboard.dart'
    show firstEnrollmentAppName, firstEnrollmentDeviceName;
import 'package:at_auth/at_auth.dart' show AtOnboardingRequest;
import 'package:test/test.dart';

/// What a client holding NO enrollment asks its first one to be.
///
/// A pre-enrollment atSign has no enrollment record, so nothing can be carried
/// over the way a retrofit of an existing enrollment carries its predecessor's
/// app, device and grants. These are the values it invents instead, and each
/// one is a decision with a consequence on the atServer.
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

    /// ⛔ The property this file exists for.
    ///
    /// Sibling clones of one pre-enrollment keyfile each retrofit to their own
    /// enrollment, and the atServer refuses a request naming an
    /// `(appName, deviceName)` that an approved enrollment already holds —
    /// measured against a live atServer, which answered *"Another enrollment
    /// with id … exists with the app name: … and device name: … in approved
    /// state"*. So a shared constant lets the FIRST device upgrade and leaves
    /// every other one refused at every start, for ever, with nothing on the
    /// device saying why.
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

  /// The constants are declared in at_client because two of its paths need
  /// them, while at_auth carries the same values as field defaults on
  /// [AtOnboardingRequest] — a default is not a constant this package can
  /// reference, so nothing but this pins the two together.
  group('the first-enrollment constants match at_auth\'s own defaults', () {
    final request = AtOnboardingRequest('@alice');

    test('appName', () {
      expect(firstEnrollmentAppName, request.appName);
    });

    test('deviceName', () {
      expect(firstEnrollmentDeviceName, request.deviceName);
    });
  });
}
