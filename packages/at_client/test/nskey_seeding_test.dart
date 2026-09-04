import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

/// Which namespaces a client seeds at start.
///
/// This decides how much of the fleet ends up with keys before the PQ flag
/// flips anywhere, so the two populations that matter are the ones with the
/// least to go on: a legacy client, which can name no enrollment and so has
/// no record it can read its grants from, and a wildcard enrollment, whose
/// authorisation cannot be enumerated.
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
      {bool answer = false,
      bool throws = false}) {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    final asked = <NskeyRotationContext>[];
    return (
      seeding: NskeySeeding(
        atClient: atClient,
        ring: _RingAnswering(atClient, published),
        rotationPolicy: (ns) {
          asked.add(ns);
          if (throws) throw StateError('the application\'s policy blew up');
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

  test('a policy that throws rotates nothing, and does not fail the caller',
      () async {
    // What a caller is doing when the policy is consulted is reaching this
    // atSign or writing to it, and neither is broken by a rotation that did
    // not happen: the published generation stays published and the question is
    // put again at the next start. Letting the exception out would turn an
    // application's bug in its own closure into a failed write.
    final w = withPublished(
        NskeyAdvertisement.single(
          publicKey: Uint8List.fromList(List<int>.filled(1216, 7)),
          alg: SecretSharingAlgos.xWing,
          createdAt: DateTime.utc(2020),
        ),
        throws: true);

    expect(await w.seeding.rotateIfPolicyAsks(atSign, 'app_1.my_apps'), isFalse,
        reason: 'the throw is swallowed and reported as "did not rotate", '
            'rather than propagating into whatever write asked');
    expect(w.asked, hasLength(1),
        reason: 'the control: the policy really was consulted, so the false '
            'above is the exception being caught and not a question never '
            'put');
  });

  test('a legacy client seeds the one namespace it can name', () async {
    final s = seeding(preferenceNamespace: 'wavi');

    expect(await s.authorisedNamespaces(), {'wavi'},
        reason: 'a legacy client can name no enrollment, so its preference '
            'namespace is the only list it has — and such clients are most of '
            'the fleet during the rollout, so this is where seeding coverage '
            'actually comes from');
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

  group('the rotation question follows the route that asked to seed', () {
    // `AtClient.ensureReachable` reads what is published, finds nothing, and
    // then `NskeySeeding.seedNamespace` reads again — two reads of the same
    // record with the seed's decision between them. A sibling enrollment
    // publishing in that window routes the second read onto the branch that
    // puts the rotation question, from a route that never offers it.

    /// The generation a sibling publishes mid-route. Dated far enough back
    /// that any policy with an opinion about age would say replace it, so a
    /// zero ask count is the question not being put rather than a policy
    /// declining to answer.
    NskeyAdvertisement sibling() => NskeyAdvertisement.single(
          publicKey: Uint8List.fromList(List<int>.filled(1216, 7)),
          alg: SecretSharingAlgos.xWing,
          createdAt: DateTime.utc(2020),
        );

    ({NskeySeeding seeding, List<NskeyRotationContext> asked}) wired() {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      final asked = <NskeyRotationContext>[];
      return (
        seeding: NskeySeeding(
          atClient: atClient,
          ring: _RingPublishingLate(atClient, sibling()),
          rotationPolicy: (context) {
            asked.add(context);
            return true;
          },
        ),
        asked: asked,
      );
    }

    int readsBy(NskeySeeding seeding) =>
        (seeding.ring as _RingPublishingLate).reads;

    /// `AtClient.ensureReachable`'s branches, in its order: the namespace
    /// check that costs nothing, its own read of what is published, and then
    /// the seed with the argument that route passes. An `AtClientImpl` cannot
    /// be driven from here — it builds its own key ring and nothing can
    /// replace it — so this walks the same sequence over a ring that can be.
    Future<void> reachabilityRoute(NskeySeeding seeding, String ns) async {
      if (!NskeySeeding.isSeedable(ns)) return;
      if (await seeding.ring.publishedAdvertisement(atSign, ns) != null) return;
      await seeding.seedNamespace(atSign, ns, askRotationPolicy: false);
    }

    test('a sibling publishing mid-route does not become a rotation', () async {
      // ⚠️ A discriminator, not a restatement of the parameter: the ring below
      // really does take `seedNamespace` into its published branch, which is
      // the only branch that puts the question. Before the parameter existed
      // this recorded ONE ask, and the mutation that records one again is to
      // have the route pass `askRotationPolicy` defaulted.
      final w = wired();

      await reachabilityRoute(w.seeding, 'app_1.my_apps');

      expect(readsBy(w.seeding), 2,
          reason: 'both reads happened — the route\'s own and '
              'seedNamespace\'s — so the second landed on the published '
              'branch and adopted the sibling\'s generation rather than '
              'minting past it');
      expect(w.asked, isEmpty,
          reason: 'the rotation lever belongs to the startup sweep and to the '
              'conveyance of a content key. A call whose whole question is '
              'whether a peer can seal here must not spend an atSign\'s '
              'namespace key because of who won a race in its window');
    });

    test('the startup route still puts it, on the parameter\'s default',
        () async {
      // The control, and the arm most easily left out: `seedNamespace` called
      // exactly as `seed()` calls it, naming no argument at all. It stays
      // green under the mutation above, and reddens if the default is turned
      // the wrong way or the lever disabled outright.
      final w = wired();
      expect(
          await w.seeding.ring.publishedAdvertisement(atSign, 'app_1.my_apps'),
          isNull,
          reason: 'the ring\'s cold answer, consumed so that this arm and the '
              'one above differ ONLY in the argument passed — both reach '
              'seedNamespace with the same generation published');

      await w.seeding.seedNamespace(atSign, 'app_1.my_apps');

      expect(w.asked, hasLength(1));
      expect(w.asked.single.namespace, 'app_1.my_apps',
          reason: 'the question really was put, about the namespace asked '
              'for — so the zero above is this route declining to put it and '
              'not a fixture that could never have recorded one');
    });

    test('seedNamespace refuses a namespace that can never hold a key',
        () async {
      // Every seeding route passes through here, so this is where a caller
      // that arrived by some other road is stopped. `__manage` is a grant over
      // other namespaces, not a namespace data lives in.
      final w = wired();

      await expectLater(w.seeding.seedNamespace(atSign, '__manage'),
          throwsA(isA<ArgumentError>()));

      expect(readsBy(w.seeding), 0,
          reason: 'refused from the argument alone, which is what lets '
              'ensureReachable answer notAuthorised without a round trip');
      expect(NskeySeeding.isSeedable('app_1.my_apps'), isTrue,
          reason: 'the control: an ordinary namespace is not refused, so the '
              'throw above is `__manage` and not a predicate that says no to '
              'everything');
    });
  });

  group('an add conveys only what it newly minted — UC-G2.6 c4', () {
    Future<NskeyAdvertisement> advertisement(List<String> algos,
        {DateTime? createdAt}) async {
      final keys = <PackageKey>[];
      for (final algo in algos) {
        final kem = SecretSharingAlgos.kemFor(algo)!;
        final pair = await kem.keyPairFromSeed(kem.newSeed());
        keys.add(PackageKey.fromBytes(
            use: SecretSharingAlgos.useEnc, alg: algo, pub: pair.publicKey));
      }
      return NskeyAdvertisement(
          v: nskeyAdvertisementVersion,
          createdAt: createdAt ?? DateTime.now().toUtc(),
          keys: keys);
    }

    test('exactly the new kid, and not the one already there', () async {
      final current = await advertisement([SecretSharingAlgos.xWing]);
      final widened = NskeyAdvertisement(
          v: nskeyAdvertisementVersion,
          // An add joins the CURRENT generation, so createdAt is carried.
          createdAt: current.createdAt,
          keys: [
            ...current.keys,
            (await advertisement([SecretSharingAlgos.mlKem1024])).keys.single,
          ]);

      final base =
          seeding(enrollmentId: 'enroll-a', preferenceNamespace: 'my_apps');
      final filing =
          _CountingFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign);
      await NskeySeeding(
        atClient: base.atClient,
        ring: _RingAdding(base.atClient, current, widened),
        privateFiling: filing,
      ).seedNamespace(atSign, 'my_apps');

      final newKid = widened.keys
          .firstWhere((k) => k.alg == SecretSharingAlgos.mlKem1024)
          .kid;
      expect(filing.readFor, [newKid],
          reason: 'ONE conveyance, for the kid this add minted. The other '
              'entry was in the generation before the add, so every '
              'authorised enrollment was conveyed it when it was minted — '
              're-sending it is work and noise, and the clause says neither '
              'more nor fewer');
    });

    test('and nothing at all when the add added nothing', () async {
      // ⚠️ NOT a control for the arm above — measured: a mutation removing
      // the "skip what was already there" filter reddens BOTH, because both
      // turn on that filter. This is the ZERO case of the same property: an
      // add with nothing to add must send nothing, where the arm above says
      // an add with one thing to add sends exactly that one.
      final current = await advertisement([SecretSharingAlgos.xWing]);
      final base =
          seeding(enrollmentId: 'enroll-a', preferenceNamespace: 'my_apps');
      final filing =
          _CountingFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign);

      await NskeySeeding(
        atClient: base.atClient,
        ring: _RingAdding(base.atClient, current, current),
        privateFiling: filing,
      ).seedNamespace(atSign, 'my_apps');

      expect(filing.readFor, isEmpty,
          reason: 'an add that found nothing missing returns the generation '
              'unchanged, and conveying then would re-send what the fleet '
              'already holds');
    });
  });
}

/// A ring whose published generation and add-result are both dictated, so the
/// test decides exactly what [NskeySeeding] sees before and after the add.
class _RingAdding extends PublishedNskeyKeyRing {
  _RingAdding(super.atClient, this._current, this._widened);

  final NskeyAdvertisement _current;
  final NskeyAdvertisement _widened;

  @override
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace,
          {bool useCache = true}) async =>
      _current;

  @override
  Future<NskeyAdvertisement?> add(String namespace) async => _widened;
}

/// Records which generation ids a conveyance was attempted for.
///
/// `_convey` reads the seed for a kid before anything else, so the kids that
/// arrive here are exactly the ones it set out to send — which is what "only
/// the newly minted private is conveyed" is a claim about. The COUNT is the
/// point: a test that merely checked the new kid was among them would pass
/// just as well if every kid in the generation were re-sent.
class _CountingFiling extends NskeyPrivateFiling {
  _CountingFiling({required super.keysIo, required super.atSign});

  final List<String> readFor = [];

  @override
  Future<NskeySeed?> readSeed(String namespace, String nskeyKid) async {
    readFor.add(nskeyKid);
    return null;
  }
}

/// A ring that answers nothing on its first read and an advertisement on every
/// read after it — a sibling enrollment publishing in the window between two
/// reads of the same namespace.
class _RingPublishingLate extends PublishedNskeyKeyRing {
  _RingPublishingLate(super.atClient, this._published);

  final NskeyAdvertisement _published;

  /// How many reads have been served, so a test can tell "the second read
  /// landed on the published branch" from "there was no second read".
  int reads = 0;

  @override
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace,
          {bool useCache = true}) async =>
      reads++ == 0 ? null : _published;

  /// Nothing to add, so `_addMissing` returns immediately and the only thing
  /// these tests can observe is whether the rotation policy was asked.
  @override
  Future<NskeyAdvertisement?> add(String namespace) async => null;
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
