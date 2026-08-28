import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

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

  /// Seeding wired against a ring that answers with [published], so the
  /// question the policy is asked can be observed without a live atServer.
  ({NskeySeeding seeding, List<NskeyRotationContext> asked}) withPublished(
      NskeyAdvertisement? published,
      {bool answer = false}) {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    final asked = <NskeyRotationContext>[];
    return (
      seeding: NskeySeeding(
        atClient: atClient,
        ring: _RingAnswering(atClient, published),
        rotationPolicy: (ns) {
          asked.add(ns);
          return answer;
        },
      ),
      asked: asked,
    );
  }

  test('nothing published is a cold start, and the policy is not asked',
      () async {
    // There is no generation to have an opinion about, and what a namespace
    // with none needs is a mint rather than a replacement. Asking anyway would
    // hand an application a context describing a key that does not exist.
    final w = withPublished(null, answer: true);

    expect(
        await w.seeding.rotateIfPolicyAsks(atSign, 'app_1.my_apps'), isFalse);
    expect(w.asked, isEmpty);
  });

  test('a published generation is put to the policy, with its own dates',
      () async {
    final minted = DateTime.utc(2026, 2, 3, 4, 5, 6);
    final w = withPublished(NskeyAdvertisement.single(
      publicKey: Uint8List.fromList(List<int>.filled(1216, 7)),
      alg: SecretSharingAlgos.xWing,
      createdAt: minted,
    ));

    expect(
        await w.seeding.rotateIfPolicyAsks(atSign, 'app_1.my_apps'), isFalse);

    expect(w.asked, hasLength(1));
    expect(w.asked.single.namespace, 'app_1.my_apps',
        reason: 'the namespace, so an application can answer differently for '
            'different ones — which is the whole reason this is a closure and '
            'not a duration');
    expect(w.asked.single.createdAt, minted,
        reason: 'the advertisement\'s own minted-at, not this device\'s '
            'clock: every enrollment of this atSign reads the same record and '
            'must reach the same answer');
    expect(w.asked.single.nskeyKid, isNotEmpty);
  });

  test('a yes with no substrate to convey over rotates nothing', () async {
    // Replacing a namespace key conveys the successor to every authorised
    // enrollment. A client with nowhere to convey would publish a generation
    // only it can open, which is worse than not replacing one — so the answer
    // is honoured only where it can be carried out.
    final w = withPublished(
        NskeyAdvertisement.single(
          publicKey: Uint8List.fromList(List<int>.filled(1216, 7)),
          alg: SecretSharingAlgos.xWing,
          createdAt: DateTime.utc(2020),
        ),
        answer: true);

    expect(await w.seeding.rotateIfPolicyAsks(atSign, 'app_1.my_apps'), isFalse,
        reason: 'asked and answered yes, and still nothing rotated: this '
            'seeding has neither sharing nor filing');
    expect(w.asked, hasLength(1),
        reason: 'the control — the policy WAS consulted, so the false above '
            'is the missing substrate and not a question never put');
  });

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

  test('seeding follows the posture, and the shipped default now seeds',
      () async {
    // Minting publishes a permanent, discoverable record on the atSign, so
    // this stayed off by default while the data path was experimental. ⚠️ That
    // is what this test used to assert — "seeding is off unless the preference
    // asks for it", against a legacy default. This release candidate is the
    // one that turns it on fleet-wide: the default posture is pqReady, and
    // seeding is one of the four axes that moves with it.
    expect(AtClientPreference().seedNamespaceKeys, isTrue,
        reason: 'the shipped default is pqReady, whose whole point is that a '
            'client is READY — it holds the keys a peer needs before anyone '
            'writes post-quantum to it');
    // And the axis is still an axis: a client that names the legacy era
    // publishes nothing, which is what makes a compatibility test possible.
    expect(AtClientPreference(posture: PqPosture.legacy).seedNamespaceKeys,
        isFalse,
        reason: 'a client asked to behave as though it were built before any '
            'of this must not publish a discoverable record');
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

/// A ring that answers [_published] for every namespace, so a test can put the
/// rotation policy a question without a live atServer.
class _RingAnswering extends PublishedNskeyKeyRing {
  _RingAnswering(super.atClient, this._published);

  final NskeyAdvertisement? _published;

  @override
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace,
          {bool useCache = true}) async =>
      _published;
}
