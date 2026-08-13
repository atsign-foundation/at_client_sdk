import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

import 'fake_enrollment_directory.dart';
import 'test_utils/envelope_tamper.dart';

class TestRegistrant
    with ApkamSigning, EnvelopeSigning, KeyPackageRegistration {
  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('TestRegistrant');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;

  TestRegistrant(this.atClient);

  /// encKeyFor is @protected — a composing mixin's business rather than an
  /// app's. Reaching it through a member of the class is what a composing
  /// mixin does, so this test double does the same thing PairwiseSecretSharing
  /// does.
  ({Uint8List secretKey, String keyAlgo})? heldKeyFor(String kid) =>
      encKeyFor(kid);
}

void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;

  final Uint8List seedA = Uint8List.fromList(List<int>.generate(32, (i) => i));
  late Uint8List publicKeyA;

  setUpAll(() async {
    registerFallbackValue(AtKey());
    publicKeyA =
        (await XWingPureDartAlgo.instance.generateKeyPair(seedA)).publicKey;
  });

  MockAtClient buildMockClient(String enrollmentId) =>
      buildRemoteBackedMockClient(
          atSign: atSign, enrollmentId: enrollmentId, remoteData: remoteData);

  TestRegistrant buildRegistrant(
      String enrollmentId, FakeEnrollmentDirectory directory,
      {Uint8List? seed}) {
    final registrant = TestRegistrant(buildMockClient(enrollmentId))
      ..directory = directory;
    if (seed != null) {
      registrant.loadApkamKeys =
          () async => PersistedApkamKeys.single(encSeed: base64Encode(seed));
    }
    return registrant;
  }

  setUp(() {
    remoteData = {};
  });

  group('register', () {
    test(
        'publishes the _apsk signing key and returns a key package with an '
        'x-wing enc key (nothing is published as an at-key)', () async {
      final registrant =
          buildRegistrant('enroll-a', FakeEnrollmentDirectory(), seed: seedA);
      final keyPackage = await registrant.register();

      expect(keyPackage.enrollmentId, 'enroll-a');
      expect(registrant.isRegistered, isTrue);

      // the _apsk signing key was published so peers can verify envelopes
      expect(remoteData['public:_apsk.enroll-a.a.__e$atSign'],
          await registrant.publicSigningKey);

      // the returned key package carries the x-wing enc key; register() does
      // NOT write it anywhere (it rides enroll:request), and nothing is
      // published as a hidden at-key
      final encKey = keyPackage.bestKeyFor(SecretSharingAlgos.keyAlgos);
      expect(encKey, isNotNull);
      expect(encKey!.alg, SecretSharingAlgos.xWing);
      expect(encKey.use, SecretSharingAlgos.useEnc);
      expect(encKey.pub, base64Encode(publicKeyA));
      expect(registrant.kpid, encKey.kid);
      expect(remoteData.keys.where((k) => k.contains('__sskb')), isEmpty);
    });

    test('generates and saves a fresh enc keypair when no loader is supplied',
        () async {
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory();
      PersistedApkamKeys? saved;
      registrant.saveApkamKeys = (keys) async => saved = keys;

      final keyPackage = await registrant.register();
      expect(saved, isNotNull);
      // the persisted seed deterministically re-derives the registered key
      final rederived = await XWingPureDartAlgo.instance
          .generateKeyPair(base64Decode(saved!.encKeys.single.encSeed));
      expect(base64Encode(rederived.publicKey),
          keyPackage.bestKeyFor(SecretSharingAlgos.keyAlgos)!.pub);
    });

    test('loadApkamKeys gives a stable kpid across instances', () async {
      final r1 =
          buildRegistrant('enroll-a', FakeEnrollmentDirectory(), seed: seedA);
      final r2 =
          buildRegistrant('enroll-a', FakeEnrollmentDirectory(), seed: seedA);
      await r1.register();
      await r2.register();
      expect(r1.kpid, r2.kpid); // same seed -> same enc keypair -> same kpid
    });
  });

  group('the configured KEM decides what is minted', () {
    TestRegistrant registrantFor(String keyAlgo) {
      final client = buildMockClient('enroll-a');
      // MockAtClient's getPreferences() is concrete and returns a stable,
      // mutable instance — the same shape as the real one, so setting the
      // knob here is what an app does.
      client.getPreferences().keyEstablishmentAlgo = keyAlgo;
      return TestRegistrant(client)..directory = FakeEnrollmentDirectory();
    }

    test('the hybrid is what an unconfigured client mints', () async {
      final pkg = await registrantFor(SecretSharingAlgos.xWing).register();
      final encKey = pkg.bestKeyFor(SecretSharingAlgos.keyAlgos)!;

      expect(encKey.alg, SecretSharingAlgos.xWing);
      expect(base64Decode(encKey.pub),
          hasLength(XWingPureDartAlgo.publicKeyLength));
      expect(pkg.suites, [
        SecretSharingAlgos.xWingRfc9180,
        SecretSharingAlgos.xWingHpke,
      ]);
    });

    test('a client configured for ML-KEM-1024 mints and advertises it',
        () async {
      final registrant = registrantFor(SecretSharingAlgos.mlKem1024);
      final pkg = await registrant.register();
      final encKey = pkg.bestKeyFor(SecretSharingAlgos.keyAlgos)!;

      expect(registrant.encKeyAlgo, SecretSharingAlgos.mlKem1024);
      expect(encKey.alg, SecretSharingAlgos.mlKem1024);
      expect(base64Decode(encKey.pub),
          hasLength(MlKem1024PureDartAlgo.publicKeyLength),
          reason: '1568 bytes against the hybrid\'s 1216 — the two arms are '
              'not even the same shape');
      expect(pkg.suites, [SecretSharingAlgos.mlKem1024Rfc9180],
          reason: 'and it must not claim the X-Wing constructions, which '
              'nothing it holds can decapsulate');
    });

    test('the persisted seed re-derives an ML-KEM package', () async {
      // The trap the seed contract exists for. ML-KEM's `secretKey` is the
      // 3168-byte expanded decapsulation key and cannot be fed back as a
      // seed, so persisting it — which is correct for X-Wing, where the two
      // are the same bytes — would leave this key unrecoverable at the next
      // start, and the client would answer at a kpid nobody writes to.
      final registrant = registrantFor(SecretSharingAlgos.mlKem1024);
      PersistedApkamKeys? saved;
      registrant.saveApkamKeys = (keys) async => saved = keys;
      final pkg = await registrant.register();

      expect(saved!.encKeys.single.keyAlgo, SecretSharingAlgos.mlKem1024,
          reason: 'the algorithm travels with the seed: 32 and 64 bytes are '
              'both valid seeds for some backend, so the bytes alone do not '
              'say which');
      expect(base64Decode(saved!.encKeys.single.encSeed),
          hasLength(MlKem1024PureDartAlgo.seedLength));

      final rederived = await MlKem1024PureDartAlgo.instance
          .keyPairFromSeed(base64Decode(saved!.encKeys.single.encSeed));
      expect(base64Encode(rederived.publicKey),
          pkg.bestKeyFor(SecretSharingAlgos.keyAlgos)!.pub);
    });

    test('a loaded key keeps its own algorithm whatever the preference says',
        () async {
      // The kpid is the address peers already seal to, and it is frozen in an
      // enrollment record that is never rewritten. Re-minting under a newly
      // configured KEM would move this client to an address nobody writes to.
      final registrant = registrantFor(SecretSharingAlgos.mlKem1024);
      registrant.loadApkamKeys = () async => PersistedApkamKeys.single(
          encSeed: base64Encode(seedA), keyAlgo: SecretSharingAlgos.xWing);

      final pkg = await registrant.register();

      expect(registrant.configuredKeyAlgo, SecretSharingAlgos.mlKem1024);
      expect(registrant.encKeyAlgo, SecretSharingAlgos.xWing);
      expect(pkg.bestKeyFor(SecretSharingAlgos.keyAlgos)!.pub,
          base64Encode(publicKeyA));
    });

    test('an unimplemented algorithm fails rather than minting something else',
        () async {
      await expectLater(registrantFor('kyber-1024-v9').register(),
          throwsA(isA<StateError>()));
    });
  });

  group('holding more than one enc key', () {
    // ML-KEM seeds are the 64-byte d||z, not X-Wing's 32.
    final Uint8List mlSeed =
        Uint8List.fromList(List<int>.generate(64, (i) => 200 - i));
    late Uint8List mlPublicKey;

    setUpAll(() async {
      mlPublicKey = (await MlKem1024PureDartAlgo.instance
              .keyPairFromSeed(mlSeed))
          .publicKey;
    });

    /// A client restarting after a rotation: it advertises the ML-KEM key and
    /// retains the X-Wing one it used to be reached at.
    ///
    /// The retired key is the X-Wing one deliberately, because X-Wing is FIRST
    /// in SecretSharingAlgos.keyAlgos — so preference order alone would pick
    /// it and only status can send the active key to the ML-KEM entry.
    TestRegistrant rotated() {
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory();
      registrant.loadApkamKeys = () async => PersistedApkamKeys(encKeys: [
            PersistedEncKey(
                encSeed: base64Encode(seedA),
                keyAlgo: SecretSharingAlgos.xWing,
                status: KeyEntryStatus.retired),
            PersistedEncKey(
                encSeed: base64Encode(mlSeed),
                keyAlgo: SecretSharingAlgos.mlKem1024),
          ]);
      return registrant;
    }

    test('both keys are expanded, and the active one is the address', () async {
      final registrant = rotated();
      final pkg = await registrant.register();

      expect(registrant.encKeyAlgo, SecretSharingAlgos.mlKem1024);
      expect(registrant.encPublicKey, mlPublicKey);
      expect(registrant.kpid, PackageKey.computeKid(base64Encode(mlPublicKey)));
      expect(registrant.kpid,
          isNot(PackageKey.computeKid(base64Encode(publicKeyA))),
          reason: 'the retired X-Wing key is what preference order would have '
              'reached first');
      expect(pkg.kpid, registrant.kpid,
          reason: 'the holder and its advertised package must agree about the '
              'address, or the client listens where nobody writes');
    });

    test('the package advertises the retired key too, saying so', () async {
      final pkg = await rotated().register();

      expect(pkg.keys, hasLength(2));
      final retired = pkg.keys.singleWhere((k) => k.alg == SecretSharingAlgos.xWing);
      expect(retired.status, KeyEntryStatus.retired);
      expect(retired.pub, base64Encode(publicKeyA));
      expect(
          pkg.keys
              .singleWhere((k) => k.alg == SecretSharingAlgos.mlKem1024)
              .status,
          KeyEntryStatus.active);
      expect(pkg.suites, contains(SecretSharingAlgos.mlKem1024Rfc9180));
    });

    test('a retired key is still held, and still opens what named it',
        () async {
      final registrant = rotated();
      await registrant.register();

      final retiredKid = PackageKey.computeKid(base64Encode(publicKeyA));
      expect(registrant.heldKpids, {registrant.kpid, retiredKid},
          reason: 'both addresses are swept, or an envelope in flight to the '
              'old one is never even looked for');

      final held = registrant.heldKeyFor(retiredKid);
      expect(held, isNotNull);
      expect(held!.keyAlgo, SecretSharingAlgos.xWing);
      final rederived =
          await XWingPureDartAlgo.instance.keyPairFromSeed(seedA);
      expect(held.secretKey, rederived.secretKey);

      expect(registrant.heldKeyFor('not-a-kid-this-client-holds'), isNull);
    });

    test('a holding with nothing active refuses rather than picking one',
        () async {
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory();
      registrant.loadApkamKeys = () async => PersistedApkamKeys(encKeys: [
            PersistedEncKey(
                encSeed: base64Encode(seedA),
                status: KeyEntryStatus.retired),
          ]);

      await expectLater(
          registrant.register(),
          throwsA(isA<StateError>().having(
              (e) => '$e', 'message', contains('every one of them is retired'))),
          reason: 'a retired key is retained to open what is in flight to it, '
              'not to be reached at — advertising one as the address would '
              'point every peer at a key this client has withdrawn');
    });

    test('an empty holding refuses rather than minting behind the app\'s back',
        () async {
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory();
      registrant.loadApkamKeys = () async => PersistedApkamKeys(encKeys: []);

      await expectLater(registrant.register(), throwsA(isA<StateError>()),
          reason: 'null means "nothing to restore, mint one"; an empty list '
              'says "these are the keys" and names none, and minting anyway '
              'answers at an address the enrollment never advertised');
    });
  });

  group('KeyPackage parsing', () {
    test(
        'unknown-alg entries are kept, malformed entries skipped, bestKeyFor '
        'honours preference order', () {
      final pkg = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          {'kid': 'k1', 'use': 'enc', 'alg': 'x-wing-99', 'pub': 'future-pub'},
          {'kid': 'k2', 'use': 'enc', 'alg': 'rsa-2048', 'pub': 'rsa-pub'},
          {'kid': 'k3', 'use': 'enc'}, // malformed: no alg/pub
          'not even a map',
        ],
        // Named, because a package that names no suites is refused outright —
        // and what this test is about is the ENTRIES, not the suites.
        'suites': ['x-wing-hpke-v1'],
      }, enrollmentId: 'enroll-x', apkamId: 'apkam-x');
      expect(pkg.keys, hasLength(2));
      expect(pkg.enrollmentId, 'enroll-x');
      expect(pkg.apkamId, 'apkam-x');
      expect(pkg.bestKeyFor(['rsa-2048'])!.kid, 'k2');
      expect(pkg.bestKeyFor(['x-wing-99', 'rsa-2048'])!.kid, 'k1');
      expect(pkg.bestKeyFor(['something-else']), isNull);
    });

    test('a retired key is kept, but is not what a sender is pointed at', () {
      final pkg = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          // The retired one FIRST, and under the stronger algorithm, so
          // preference order alone would choose it. Selection has to lose to
          // status, not merely coincide with it.
          {
            'kid': 'old',
            'use': 'enc',
            'alg': SecretSharingAlgos.xWing,
            'pub': 'b2xk',
            'status': 'retired',
          },
          {
            'kid': 'new',
            'use': 'enc',
            'alg': SecretSharingAlgos.mlKem1024,
            'pub': 'bmV3',
          },
        ],
        'suites': ['x-wing-hpke-v1'],
      }, enrollmentId: 'enroll-x');

      expect(pkg.keys, hasLength(2),
          reason: 'a retired entry is retained — the holder can still open '
              'what was already sealed to it');
      expect(pkg.bestKeyFor(SecretSharingAlgos.keyAlgos)!.kid, 'new');
      expect(pkg.kpid, 'new',
          reason: 'the address senders use from now on is the active key');
      expect(pkg.bestKeyFor([SecretSharingAlgos.xWing]), isNull,
          reason: 'asking for the retired key by its algorithm still gets '
              'nothing — the answer is about status, not about ordering');
    });

    test('a package whose every key is retired points a sender nowhere', () {
      final pkg = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          {
            'kid': 'old',
            'use': 'enc',
            'alg': SecretSharingAlgos.xWing,
            'pub': 'b2xk',
            'status': 'retired',
          },
        ],
        'suites': ['x-wing-hpke-v1'],
      }, enrollmentId: 'enroll-x');

      expect(pkg.kpid, isNull);
      // requestSecretsFromNamespace and shareSecretWithNamespace both skip a
      // member whose kpid is null, so a holder that has retired everything is
      // passed over rather than sealed to at an address it has withdrawn.
      expect(pkg.bestKeyFor(SecretSharingAlgos.keyAlgos), isNull);
    });

    test('a package that names no suites is refused, not read as the oldest',
        () {
      // It used to be read as "the one construction that existed before the
      // field did" — a default that spoke for holders who had said nothing.
      // An enrollment key package is write-once, so that guess would have been
      // permanent for the enrollment, and sealing to a holder on a
      // construction it never claimed is exactly what cannot be recovered
      // from: the holder simply cannot open what arrives.
      expect(
          () => KeyPackage.fromPayload({
                'v': 1,
                'createdAt': '2026-06-11T00:00:00.000Z',
                'keys': [
                  {'kid': 'k1', 'use': 'enc', 'alg': 'x-wing', 'pub': 'cA=='},
                ],
              }, enrollmentId: 'enroll-x'),
          throwsA(isA<FormatException>()));
    });

    test('a declared suites list is what the sender negotiates against', () {
      final pkg = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          {'kid': 'k1', 'use': 'enc', 'alg': 'x-wing', 'pub': 'p'},
        ],
        // A holder that has upgraded past this build, plus an entry this build
        // has never heard of — kept, because it is the holder's claim about
        // itself, not ours.
        'suites': ['x-wing-hpke-v2', SecretSharingAlgos.xWingHpke, 7],
      }, enrollmentId: 'enroll-x');

      expect(pkg.suites, ['x-wing-hpke-v2', SecretSharingAlgos.xWingHpke],
          reason: 'non-String entries are dropped the same way malformed key '
              'entries are, rather than throwing');
      expect(pkg.bestSuiteFor(['x-wing-hpke-v2', SecretSharingAlgos.xWingHpke]),
          'x-wing-hpke-v2',
          reason: 'the sender\'s order decides, strongest first');
      expect(pkg.bestSuiteFor([SecretSharingAlgos.xWingHpke]),
          SecretSharingAlgos.xWingHpke);
    });

    test('no overlap is null rather than a guess', () {
      // Stamping the sender's own preference anyway would hand the holder an
      // envelope it cannot unwrap, and the failure would surface as an opaque
      // AEAD error on the far side rather than a refusal here.
      final pkg = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': <Object?>[],
        'suites': ['x-wing-hpke-v9'],
      }, enrollmentId: 'enroll-x');

      expect(pkg.bestSuiteFor(SecretSharingAlgos.suites), isNull);
    });

    test('what gets written declares what the advertised keys can open', () {
      // The two arms differ in exactly one input — the KEM the advertised key
      // names — and no suite appears in both. Anything that derived `suites`
      // from the build's own list instead would produce the identical
      // three-suite answer for both, so this fails loudly if the derivation is
      // reintroduced.
      final xWingPayload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.xWing,
              pub: 'cA=='),
        ],
      );
      expect(xWingPayload['suites'],
          [SecretSharingAlgos.xWingRfc9180, SecretSharingAlgos.xWingHpke],
          reason: 'an X-Wing private opens both X-Wing constructions — the '
              'difference between them is the key schedule and the AEAD, not '
              'the decapsulation');
      expect(xWingPayload['suites'],
          isNot(contains(SecretSharingAlgos.mlKem1024Rfc9180)),
          reason: 'and nothing it holds can open an ML-KEM-1024 envelope');

      final mlKemPayload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.mlKem1024,
              pub: 'cA=='),
        ],
      );
      expect(mlKemPayload['suites'], [SecretSharingAlgos.mlKem1024Rfc9180]);
      expect(mlKemPayload['suites'],
          isNot(contains(SecretSharingAlgos.xWingRfc9180)));
    });

    test('a package advertising no key claims no suite', () {
      // Rather than the build's whole list. This is the shape the enrollment
      // record freezes, and a holder with nothing to decapsulate with can open
      // nothing whatever this build supports.
      final payload = KeyPackage.payloadFor(
          createdAt: DateTime.utc(2026), keys: const []);
      expect(payload['suites'], isEmpty);
    });

    test('an unrecognised key algorithm contributes no suite', () {
      // Fails closed: a holder must not have a suite claimed on its behalf on
      // the strength of a key this build cannot identify, because a sender
      // acts on the claim and the failure lands on the holder.
      final payload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc, alg: 'kyber-1024-v9', pub: 'cA=='),
        ],
      );
      expect(payload['suites'], isEmpty);
    });

    test('malformed payload throws FormatException', () {
      expect(() => KeyPackage.fromPayload({'v': 'one'}, enrollmentId: 'e'),
          throwsA(isA<FormatException>()));
      expect(() => KeyPackage.fromPayload('a string', enrollmentId: 'e'),
          throwsA(isA<FormatException>()));
    });

    test('toJson is the payload only — identity is carried by the verb', () {
      final pkg = KeyPackage(
          enrollmentId: 'e',
          apkamId: 'a',
          createdAt: DateTime.utc(2026, 6, 11),
          keys: [PackageKey(use: 'enc', alg: 'x-wing', pub: 'cA==')]);
      final json = pkg.toJson();
      expect(json.containsKey('enrollmentId'), isFalse);
      expect(json.containsKey('apkamId'), isFalse);
      expect(json['v'], KeyPackage.currentVersion);
      expect((json['keys'] as List), hasLength(1));
    });
  });

  /// A key package *is* an encapsulation target: whoever's X-Wing key ends up
  /// in one is who this atSign's other clients seal their secrets to. So it is
  /// advertised as an APKAM-signed envelope and verified against the
  /// advertising enrollment's `_apsk` before the key inside is used. A package
  /// that does not verify drops that member alone — the member is simply never
  /// sealed to, which is fail-closed for them and no worse for anybody else.
  group('VerbEnrollmentDirectory', () {
    /// A registered enrollment whose `_apsk` is published (into the shared
    /// `remoteData`, which every mock client in this file reads).
    Future<TestRegistrant> registered(String enrollmentId,
        {Uint8List? seed}) async {
      final r = buildRegistrant(enrollmentId, FakeEnrollmentDirectory(),
          seed: seed ?? seedA);
      await r.register();
      return r;
    }

    void stubListns(AtClient atClient, List<Object?> records) {
      // Resolve the secondary first: nesting the call inside `when` would
      // register the stub against getRemoteSecondary itself.
      final secondary = atClient.getRemoteSecondary()!;
      when(() => secondary.executeCommand('enroll:listns:myapp\n', auth: true))
          .thenAnswer((_) async => 'data:${jsonEncode(records)}');
    }

    Map<String, Object?> record(String enrollmentId, Object? keyPackage,
            {String access = 'rw'}) =>
        {
          'enrollmentId': enrollmentId,
          'access': access,
          'apkamPubKey': 'pk-$enrollmentId',
          'metadata': keyPackage == null ? {} : {'keyPackage': keyPackage},
        };

    test(
        'listForNamespace parses members + signed key packages and honours '
        'exclude', () async {
      final b = await registered('enroll-b');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [
        record('enroll-b', await b.signedKeyPackagePayload()),
        record('enroll-c', null, access: 'r'),
      ]);

      final directory = VerbEnrollmentDirectory(atClient);
      final members = await directory.listForNamespace('myapp');
      expect(
          members.map((m) => m.enrollmentId).toSet(), {'enroll-b', 'enroll-c'});

      final mb = members.firstWhere((m) => m.enrollmentId == 'enroll-b');
      expect(mb.access, 'rw');
      expect(mb.keyPackage, isNotNull);
      // apkamId is populated from the record's apkamPubKey, not the payload
      expect(mb.keyPackage!.apkamId, 'pk-enroll-b');
      expect(mb.keyPackage!.bestKeyFor(SecretSharingAlgos.keyAlgos)!.pub,
          base64Encode(publicKeyA));

      // An enrollment that advertised nothing is ordinary, not an error: it
      // is returned, simply without a package to seal to.
      expect(members.firstWhere((m) => m.enrollmentId == 'enroll-c').keyPackage,
          isNull);

      final excluded = await directory
          .listForNamespace('myapp', excludeEnrollmentIds: {'enroll-b'});
      expect(excluded.map((m) => m.enrollmentId), ['enroll-c']);
    });

    test('an unsigned key package is not sealed to', () async {
      final b = await registered('enroll-b');
      final atClient = buildMockClient('enroll-self');
      // The bare payload, as it was advertised before signing landed.
      stubListns(atClient, [record('enroll-b', b.myKeyPackage.toJson())]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull,
          reason: 'accepting a bare package would leave the encapsulation '
              'target only as trustworthy as whatever served the record');
    });

    test('a key package signed by another enrollment is not sealed to',
        () async {
      // enroll-b's record, carrying a package enroll-d signed. Accepting it
      // would hand enroll-d every secret meant for enroll-b.
      final d = await registered('enroll-d');
      final atClient = buildMockClient('enroll-self');
      stubListns(
          atClient, [record('enroll-b', await d.signedKeyPackagePayload())]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull);
    });

    test('a key package that lies about who signed it is not sealed to',
        () async {
      // The attack the signature actually stops. Someone who can write the
      // enrollment record makes the claim match — envelope enrollmentId,
      // record enrollmentId, all "enroll-b" — and signs with their own key.
      // Every structural check passes; only verifying against enroll-b's real
      // _apsk catches it.
      final d = await registered('enroll-d');
      // Stamped at signing time, not edited afterwards: the claim is inside
      // the protected header, so a forger has to sign it that way — which
      // anyone with their own key can do, and which is exactly why the claim
      // is worth nothing until it is checked against enroll-b's own _apsk.
      final forged = signEnvelope(d.myKeyPackage.toJson(),
          keys: [(await d.signingKeys).first], enrollmentId: 'enroll-b');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', forged)]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull,
          reason: 'the claim is free to forge; the signature over it is not');
    });

    test('a tampered key package is not sealed to', () async {
      final b = await registered('enroll-b');
      // Signature intact over the original body; only the advertised key is
      // swapped, which is the substitution that matters.
      final envelope = (await b.signedKeyPackagePayload()).withPayloadJson({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          {'kid': 'evil', 'use': 'enc', 'alg': 'x-wing', 'pub': 'evil-pub'}
        ],
      });
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', envelope)]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull);
    });

    test('each member says why it has no usable key package', () async {
      final b = await registered('enroll-b');
      final d = await registered('enroll-d');
      // Registered so its OWN _apsk is published: the package below must
      // genuinely verify and then fail to PARSE. Signed by another
      // enrollment it would fail verification first and never reach the
      // parse, which is a different outcome entirely.
      final future = await registered('enroll-future');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [
        record('enroll-b', await b.signedKeyPackagePayload()),
        record('enroll-none', null),
        // enroll-b's record carrying a package enroll-d signed: refused.
        record('enroll-wrong', await d.signedKeyPackagePayload()),
        // Signed by the right enrollment, but a payload this version cannot
        // read — what a newer client's package looks like from here.
        record(
            'enroll-future',
            signEnvelope({'shape': 'from a later version'},
                keys: [(await future.signingKeys).first],
                enrollmentId: 'enroll-future')),
      ]);

      final byId = {
        for (final m in await VerbEnrollmentDirectory(atClient)
            .listForNamespace('myapp'))
          m.enrollmentId: m
      };

      expect(byId['enroll-b']!.keyPackageStatus, KeyPackageStatus.present);
      expect(byId['enroll-none']!.keyPackageStatus, KeyPackageStatus.absent,
          reason: 'an enrollment that advertised nothing is ordinary — an old '
              'client, or the self-retrofit path, which needs no conveyance');
      expect(byId['enroll-wrong']!.keyPackageStatus, KeyPackageStatus.rejected,
          reason: 'a package offered under the wrong enrollment is the one '
              'case a caller must refuse rather than skip');
      expect(
          byId['enroll-future']!.keyPackageStatus, KeyPackageStatus.unsupported,
          reason: 'nobody here can fix a package written by a newer client, so '
              'refusing would block work purely because the other end is '
              'ahead of us');

      // Only `present` carries a package; the rest are all null, which is
      // exactly why the status is needed to tell them apart.
      expect(
          byId.values
              .where((m) => m.keyPackage != null)
              .map((m) => m.enrollmentId),
          ['enroll-b']);
    });

    test(
        'a package that names no enrollment still verifies — the record says '
        'whose it is', () async {
      // The enroll:request shape: signed before the atServer assigned an id,
      // so there was nothing truthful to stamp. Rejecting it would refuse
      // every key package that rides an enrollment request.
      final b = await registered('enroll-b');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [
        record(
            'enroll-b',
            signEnvelope(b.myKeyPackage.toJson(),
                keys: [(await b.signingKeys).first], enrollmentId: null)),
      ]);

      final member =
          (await VerbEnrollmentDirectory(atClient).listForNamespace('myapp'))
              .single;

      expect(member.keyPackageStatus, KeyPackageStatus.present);
      expect(member.keyPackage!.enrollmentId, 'enroll-b',
          reason: 'injected from the record, which is where the id has always '
              'lived — the payload never carried it');
    });

    // Two tests here re-ran the pair above in "the JWS wrapper" — a package
    // read and sealed to, and one claiming another signer in its kid. There
    // is one shape now, so both were the same tests twice.

    test('an envelope version this build cannot verify is rejected', () async {
      // The version rides inside the protected header, so an envelope from a
      // later shape cannot be checked at all — and an unverifiable package is
      // only as trustworthy as whatever served the record, whatever the
      // reason. That makes it `rejected`, not the `unsupported` a merely
      // newer PAYLOAD gets: that one verified first, and this one cannot.
      final b = await registered('enroll-b');
      final envelope = (await b.signedKeyPackagePayload())
          .claiming({'alg': 'RS256', 'kid': 'enroll-b', 'v': 2});
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', envelope)]);

      final member =
          (await VerbEnrollmentDirectory(atClient).listForNamespace('myapp'))
              .single;

      expect(member.keyPackageStatus, KeyPackageStatus.rejected);
    });

    test('a package whose protected header cannot be read is rejected',
        () async {
      final b = await registered('enroll-b');
      // Built through the raw JSON, because the type refuses this at parse:
      // an entry whose header cannot be read is not an entry, which is the
      // property under test one layer down.
      final signed = signEnvelope(b.myKeyPackage.toJson(),
          keys: [(await b.signingKeys).first], enrollmentId: 'enroll-b');
      final envelope = {
        ...signed.toJson(),
        'signatures': [
          {...signed.signature.toJson(), 'protected': 'not!!!base64url'}
        ],
      };
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', envelope)]);

      final member =
          (await VerbEnrollmentDirectory(atClient).listForNamespace('myapp'))
              .single;

      expect(member.keyPackageStatus, KeyPackageStatus.rejected,
          reason: 'this wrapper version is one this build knows; a claim that '
              'cannot be read out of it is malformation, not novelty');
    });

    test('one bad advertisement does not cost the other members theirs',
        () async {
      final b = await registered('enroll-b');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [
        record('enroll-bad', {'not': 'an envelope'}),
        record('enroll-b', await b.signedKeyPackagePayload()),
      ]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.map((m) => m.enrollmentId).toSet(),
          {'enroll-bad', 'enroll-b'});
      expect(
          members.firstWhere((m) => m.enrollmentId == 'enroll-bad').keyPackage,
          isNull);
      expect(members.firstWhere((m) => m.enrollmentId == 'enroll-b').keyPackage,
          isNotNull,
          reason: 'throwing on a bad record would let one enrollment deny '
              'every other one its secrets');
    });
  });
}
