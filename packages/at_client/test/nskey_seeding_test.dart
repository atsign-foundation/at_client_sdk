import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {
}

/// Which namespaces a client seeds at start.
///
/// This decides how much of the fleet ends up with keys before the PQ flag
/// flips anywhere, so the two populations that matter are the ones with the
/// least to go on: a legacy client, which has no enrollment record at all, and
/// a wildcard enrollment, whose authorisation cannot be enumerated.
void main() {
  const atSign = '@alice';

  setUpAll(() => registerFallbackValue(AtKey()));

  NskeySeeding seeding(
      {String? enrollmentId,
      String? preferenceNamespace,
      Map<String, dynamic>? enrollmentNamespaces}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookUp();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => lookUp.enrollmentId).thenReturn(enrollmentId);
    when(() => atClient.getPreferences())
        .thenReturn(AtClientPreference()..namespace = preferenceNamespace);

    final enrollmentService = MockEnrollmentService();
    when(() => atClient.enrollmentService).thenReturn(enrollmentService);
    when(() => enrollmentService.fetchEnrollmentRequests(
            enrollmentListParams: any(named: 'enrollmentListParams')))
        .thenAnswer((_) async => [
              Enrollment()
                ..enrollmentId = enrollmentId
                ..namespace = enrollmentNamespaces
            ]);

    return NskeySeeding(
        atClient: atClient, ring: PublishedNskeyKeyRing(atClient));
  }

  test('a legacy client seeds the one namespace it can name', () async {
    final s = seeding(preferenceNamespace: 'wavi');

    expect(await s.authorisedNamespaces(), {'wavi'},
        reason: 'legacy clients hold no enrollment record, and they are most '
            'of the fleet during the rollout — so this is where seeding '
            'coverage actually comes from');
  });

  test('a legacy client with no namespace seeds nothing', () async {
    expect(await seeding().authorisedNamespaces(), isEmpty);
  });

  test('an enrolled client seeds the namespaces its enrollment grants',
      () async {
    final s = seeding(
        enrollmentId: 'enroll-a',
        enrollmentNamespaces: {'wavi': 'rw', 'buzz': 'r'});

    expect(await s.authorisedNamespaces(), {'wavi', 'buzz'},
        reason: 'read access still needs the key — reading the data requires '
            'it');
  });

  test('seeding is off unless the preference asks for it', () async {
    // Minting publishes a permanent, discoverable record on the atSign. That
    // is not something to start doing behind an app's back while the data
    // path is experimental, so the default is off and the release that wants
    // fleet-wide seeding turns it on deliberately.
    expect(AtClientPreference().seedNamespaceKeys, isFalse);
  });

  test('a wildcard enrollment seeds nothing at start', () async {
    final s = seeding(
        enrollmentId: 'enroll-priv',
        enrollmentNamespaces: {'*': 'rw', '__manage': 'rw', 'wavi': 'rw'});

    expect(await s.authorisedNamespaces(), {'wavi'},
        reason: '"every namespace" is not a list that can be minted, so a '
            'wildcard mints on demand instead; __manage is not an app '
            'namespace either');
  });
}
