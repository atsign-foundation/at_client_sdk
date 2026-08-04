import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class MockEnrollmentService extends Mock implements EnrollmentService {}

class MockCryptoRollout extends Mock implements CryptoRollout {}

/// Which namespaces a client seeds at start.
///
/// This decides how much of the fleet ends up with keys before the PQ flag
/// flips anywhere, so the two populations that matter are the ones with the
/// least to go on: a legacy client, which has no enrollment record at all, and
/// a wildcard enrollment, whose authorisation cannot be enumerated.
void main() {
  const atSign = '@alice';

  setUpAll(() => registerFallbackValue(AtKey()));

  late MockCryptoRollout rollout;

  setUp(() {
    rollout = MockCryptoRollout();
    when(() => rollout.publishNotReadyIfAbsent(any()))
        .thenAnswer((_) async => true);
  });

  NskeySeeding seeding(
      {String? enrollmentId,
      String? preferenceNamespace,
      Map<String, dynamic>? enrollmentNamespaces,
      PublishedNskeyKeyRing? ring}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookupImpl();
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
        atClient: atClient,
        ring: ring ?? PublishedNskeyKeyRing(atClient),
        rollout: rollout);
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

  group('the capability marker', () {
    test('is published for a namespace that already has a key', () async {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      final ring = PublishedNskeyKeyRing(atClient)
        ..rememberOwn(atSign, 'wavi',
            (nskeyKid: 'kid-1', publicKey: Uint8List.fromList([1, 2, 3])));

      await seeding(preferenceNamespace: 'wavi', ring: ring).seed();

      verify(() => rollout.publishNotReadyIfAbsent('wavi')).called(1);
    });

    test('is published even when minting the key fails', () async {
      // The mint has no atServer to write to here, so it throws. Seeding is
      // best-effort per namespace, and what must survive that is the marker:
      // an atSign nobody can negotiate with is one nobody ever writes
      // post-quantum to, so a partly-failed seed still has to leave it
      // negotiable.
      await seeding(preferenceNamespace: 'wavi').seed();

      verify(() => rollout.publishNotReadyIfAbsent('wavi')).called(1);
    });

    test('is published for every namespace an enrollment grants', () async {
      await seeding(
          enrollmentId: 'enroll-a',
          enrollmentNamespaces: {'wavi': 'rw', 'buzz': 'r'}).seed();

      verify(() => rollout.publishNotReadyIfAbsent('wavi')).called(1);
      verify(() => rollout.publishNotReadyIfAbsent('buzz')).called(1);
    });
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
