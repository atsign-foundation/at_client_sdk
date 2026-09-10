import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'fake_enrollment_directory.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

/// A stand-in [Secret], registered as mocktail's fallback value so `any()`
/// can match one.
class FakeSecret extends Fake implements Secret {}

/// Which namespaces a client seeds at start.
void main() {
  const atSign = '@alice';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeSecret());
  });

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

  test('seeding follows the posture, and the shipped default does not seed',
      () async {
    expect(AtClientPreference().seedNamespaceKeys, isFalse,
        reason: 'the shipped default is legacy, which publishes no '
            'discoverable record at all');
    expect(AtClientPreference(posture: PqPosture.pqReady).seedNamespaceKeys,
        isTrue,
        reason: 'and pqReady is where it turns on: a client is READY when it '
            'holds the keys a peer needs before anyone writes post-quantum '
            'to it');
    expect(AtClientPreference(posture: PqPosture.legacy).seedNamespaceKeys,
        isFalse,
        reason: 'a client asked to behave as though it were built before any '
            'of this must not publish a discoverable record');
  });

  test('a wildcard enrollment seeds the namespace the app runs in', () async {
    final s = seeding(
        enrollmentId: 'enroll-priv',
        preferenceNamespace: 'buzz',
        enrollmentNamespaces: {'*': 'rw', '__manage': 'rw', 'wavi': 'rw'});
    expect(await s.authorisedNamespaces(), {'wavi', 'buzz'},
        reason: '"every namespace" is not a list that can be minted, so a '
            'wildcard grant seeds the preference namespace — exactly as the '
            'atSign\'s own credential does — beside any namespace named '
            'outright; __manage is not an app namespace');
  });
  test('a root enrollment granted only the wildcard seeds like the atSign',
      () async {
    final s = seeding(
        enrollmentId: 'enroll-root',
        preferenceNamespace: 'buzz',
        enrollmentNamespaces: {'*': 'rw', '__manage': 'rw'});
    expect(await s.authorisedNamespaces(), {'buzz'},
        reason: 'a root enrollment is the atSign\'s own privilege under '
            'another name; seeding nothing left such an atSign unreachable');
  });
  test('primary is the atSign\'s own credential and seeds the same way',
      () async {
    final s = seeding(enrollmentId: 'primary', preferenceNamespace: 'wavi');
    expect(await s.authorisedNamespaces(), {'wavi'});
  });

  group('the rotation question follows the route that asked to seed', () {
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
    /// the seed with the argument that route passes.
    Future<void> reachabilityRoute(NskeySeeding seeding, String ns) async {
      if (!NskeySeeding.isSeedable(ns)) return;
      if (await seeding.ring.publishedAdvertisement(atSign, ns) != null) return;
      await seeding.seedNamespace(atSign, ns, askRotationPolicy: false);
    }

    test('a sibling publishing mid-route does not become a rotation', () async {
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

  group('a revocation the revoker could not finish rotates at the next start',
      () {
    const ns = 'my_apps';
    final generation = NskeyAdvertisement.single(
      publicKey: Uint8List.fromList(List<int>.filled(1216, 7)),
      alg: SecretSharingAlgos.xWing,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final successor = NskeyAdvertisement.single(
      publicKey: Uint8List.fromList(List<int>.filled(1216, 11)),
      alg: SecretSharingAlgos.xWing,
      createdAt: DateTime.utc(2026, 5, 5),
    );

    /// Seeding whose namespace answer, published record and record stamp are
    /// all dictated. [revokedAt] is what the atServer reports for the
    /// namespace; [stamp] is what it reports for the advertisement record.
    ({
      NskeySeeding seeding,
      _RingRotating ring,
      FakeEnrollmentDirectory directory,
      List<NskeyRotationContext> asked,
    }) revocable({
      DateTime? revokedAt,
      DateTime? stamp,
      bool published = true,
      bool unreadable = false,
      String? enrollmentId = 'enroll-a',
    }) {
      final base = seeding(
          enrollmentId: enrollmentId,
          preferenceNamespace: ns,
          enrollmentNamespaces: {ns: 'rw'});
      final directory = FakeEnrollmentDirectory();
      if (revokedAt != null) {
        directory.authorize(ns, 'enroll-b');
        directory.revoke('enroll-b', at: revokedAt);
      }
      if (unreadable) directory.unreadableNamespaces.add(ns);

      final sharing = MockSharing();
      when(() => sharing.directory).thenReturn(directory);
      when(() => sharing.secretStore).thenReturn(SecretStore());
      when(() => sharing.pushSecretToNamespaceMembers(any(),
              excludeEnrollmentIds: any(named: 'excludeEnrollmentIds')))
          .thenAnswer((_) async => 1);

      final asked = <NskeyRotationContext>[];
      final ring = _RingRotating(
          base.atClient,
          published ? (advertisement: generation, updatedAt: stamp) : null,
          successor);
      return (
        seeding: NskeySeeding(
          atClient: base.atClient,
          ring: ring,
          sharing: sharing,
          privateFiling:
              _SeededFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign),
          rotationPolicy: (context) {
            asked.add(context);
            return false;
          },
        ),
        ring: ring,
        directory: directory,
        asked: asked,
      );
    }

    test('a revocation later than the generation replaces it, unasked',
        () async {
      final w = revocable(
          stamp: DateTime.utc(2026, 2, 1), revokedAt: DateTime.utc(2026, 3, 1));

      expect(await w.seeding.rotateIfRevoked(atSign, ns), isTrue);

      expect(w.ring.rotations, [ns]);
      expect(w.asked, isEmpty,
          reason: 'unconditional, and this fixture\'s policy answers NO: a '
              'revocation is an obligation, while the lever it would have '
              'asked governs discretionary rotation and its shipped default '
              'declines. Asking would leave the mechanism inert for everyone '
              'who has not opted in');
    });

    test('a revocation the published generation already answers does not',
        () async {
      final w = revocable(
          stamp: DateTime.utc(2026, 4, 1), revokedAt: DateTime.utc(2026, 3, 1));

      expect(await w.seeding.rotateIfRevoked(atSign, ns), isFalse);
      expect(w.ring.rotations, isEmpty);
    });

    test('no revocation does not even read what is published', () async {
      final w = revocable();

      expect(await w.seeding.rotateIfRevoked(atSign, ns), isFalse);
      expect(w.ring.reads, 0,
          reason: 'the namespace answer is asked first and settles it, so the '
              'common case — nothing was ever revoked — costs one round trip '
              'rather than two');
      expect(w.directory.lastRevokedAtQueries, [ns],
          reason: 'and it really did ask, so the zero above is a short circuit '
              'rather than a fixture that asked nothing');
    });

    test('an unreadable namespace answer rotates nothing', () async {
      final w = revocable(unreadable: true, stamp: DateTime.utc(2026, 2, 1));

      expect(await w.seeding.rotateIfRevoked(atSign, ns), isFalse);
      expect(w.ring.rotations, isEmpty);
    });

    test('a record whose stamp cannot be read rotates anyway', () async {
      final w = revocable(stamp: null, revokedAt: DateTime.utc(2026, 3, 1));

      expect(await w.seeding.rotateIfRevoked(atSign, ns), isTrue);
      expect(w.ring.rotations, [ns]);
    });

    test('nothing published is a cold start rather than a rotation', () async {
      final w =
          revocable(published: false, revokedAt: DateTime.utc(2026, 3, 1));

      expect(await w.seeding.rotateIfRevoked(atSign, ns), isFalse);
      expect(w.ring.rotations, isEmpty,
          reason: 'the mint that follows produces a generation no earlier '
              'revocation can be later than, and rotating nothing is what a '
              'ring with nothing published refuses anyway');
    });

    for (final credential in [null, EnrollmentConstants.primaryEnrollmentId]) {
      test(
          'a client running as the atSign\'s own credential (${credential ?? 'no id'}) never asks',
          () async {
        final w = revocable(
            enrollmentId: credential,
            stamp: DateTime.utc(2026, 2, 1),
            revokedAt: DateTime.utc(2026, 3, 1));

        expect(await w.seeding.rotateIfRevoked(atSign, ns), isFalse);
        expect(w.directory.lastRevokedAtQueries, isEmpty);
        expect(w.ring.rotations, isEmpty);
      });
    }

    test('seed() rotates instead of seeding the namespace', () async {
      final w = revocable(
          stamp: DateTime.utc(2026, 2, 1), revokedAt: DateTime.utc(2026, 3, 1));

      expect(await w.seeding.seed(), {ns},
          reason: 'a namespace this start published fresh material for, which '
              'is what the returned set names');
      expect(w.ring.rotations, [ns]);
      expect(w.ring.reads, 1,
          reason: 'the rotation ends the namespace\'s turn: a second read '
              'would be seedNamespace running behind it, putting the policy a '
              'question about a generation minted seconds earlier');
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
  Future<({NskeyAdvertisement advertisement, DateTime? updatedAt})?>
      publishedRecord(String owner, String namespace) async =>
          (advertisement: _current, updatedAt: null);

  @override
  Future<NskeyAdvertisement?> add(String namespace) async => _widened;
}

/// Records which generation ids a conveyance was attempted for.
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

  int reads = 0;

  @override
  Future<({NskeyAdvertisement advertisement, DateTime? updatedAt})?>
      publishedRecord(String owner, String namespace) async =>
          reads++ == 0 ? null : (advertisement: _published, updatedAt: null);

  @override
  Future<NskeyAdvertisement?> add(String namespace) async => null;
}

/// A ring that answers [_published] for every namespace, so a test can put the
/// rotation policy a question without a live atServer.
class _RingAnswering extends PublishedNskeyKeyRing {
  _RingAnswering(super.atClient, this._published);

  final NskeyAdvertisement? _published;

  @override
  Future<({NskeyAdvertisement advertisement, DateTime? updatedAt})?>
      publishedRecord(String owner, String namespace) async {
    final published = _published;
    return published == null
        ? null
        : (advertisement: published, updatedAt: null);
  }
}

/// A ring whose published record — generation and record stamp both — is
/// dictated, and whose rotate records the namespace rather than minting one.
class _RingRotating extends PublishedNskeyKeyRing {
  _RingRotating(super.atClient, this._record, this._successor);

  final ({NskeyAdvertisement advertisement, DateTime? updatedAt})? _record;
  final NskeyAdvertisement _successor;

  final List<String> rotations = [];

  int reads = 0;

  @override
  Future<({NskeyAdvertisement advertisement, DateTime? updatedAt})?>
      publishedRecord(String owner, String namespace) async {
    reads++;
    return _record;
  }

  @override
  Future<({NskeyAdvertisement rotated, NskeyAdvertisement superseded})> rotate(
      String namespace) async {
    rotations.add(namespace);
    return (rotated: _successor, superseded: _record!.advertisement);
  }
}

/// Filing that answers every seed read, so a dictated rotation can convey.
class _SeededFiling extends NskeyPrivateFiling {
  _SeededFiling({required super.keysIo, required super.atSign});

  @override
  Future<NskeySeed?> readSeed(String namespace, String nskeyKid) async =>
      NskeySeed(Uint8List.fromList(List<int>.filled(32, 9)));
}

class MockSharing extends Mock implements PairwiseSecretSharing {}
