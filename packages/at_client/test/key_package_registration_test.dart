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

  /// The `@protected` `encKeyFor`, reached the way a composing mixin reaches
  /// it.
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

      // the _apsk advertisement was published so peers can verify envelopes
      expect(remoteData['public:_apsk.enroll-a.a.__e$atSign'],
          await registrant.publicSigningKeyValue);

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
      final client = buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: 'enroll-a',
          remoteData: remoteData,
          keyEstablishmentAlgorithms: [keyAlgo]);
      return TestRegistrant(client)..directory = FakeEnrollmentDirectory();
    }

    test('the hybrid is what an unconfigured client mints', () async {
      final pkg = await registrantFor(SecretSharingAlgos.xWing).register();
      final encKey = pkg.bestKeyFor(SecretSharingAlgos.keyAlgos)!;

      expect(encKey.alg, SecretSharingAlgos.xWing);
      expect(base64Decode(encKey.pub),
          hasLength(XWingPureDartAlgo.publicKeyLength));
      expect(pkg.suites, [SecretSharingAlgos.xWingRfc9180]);
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
      // NOTE: ML-KEM's `secretKey` is the expanded decapsulation key and
      // cannot be fed back as a seed, so persisting it — correct for X-Wing,
      // where the two are the same bytes — leaves this key unrecoverable at
      // the next start.
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
      // NOTE: the kpid is the address peers already seal to, frozen in an
      // enrollment record that is never rewritten; re-minting under a newly
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
      expect(
          () => AtClientPreference(
              keyEstablishmentAlgorithms: const ['kyber-1024-v9']),
          throwsA(isA<ArgumentError>()));

      // NOTE: the register-time guard is reached by the route the preference
      // cannot police — an algorithm read back from a keyfile, filed under an
      // id this build no longer implements.
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory()
        ..loadApkamKeys = (() async => PersistedApkamKeys.single(
            encSeed: base64Encode(Uint8List(32)), keyAlgo: 'kyber-1024-v9'));
      await expectLater(registrant.register(), throwsA(isA<StateError>()));
    });
  });

  group('holding more than one enc key', () {
    // ML-KEM seeds are the 64-byte d||z, not X-Wing's 32.
    final Uint8List mlSeed =
        Uint8List.fromList(List<int>.generate(64, (i) => 200 - i));
    late Uint8List mlPublicKey;

    setUpAll(() async {
      mlPublicKey =
          (await MlKem1024PureDartAlgo.instance.keyPairFromSeed(mlSeed))
              .publicKey;
    });

    /// A client restarting after a rotation: it advertises the ML-KEM key and
    /// retains the retired X-Wing one.
    ///
    /// X-Wing is first in `SecretSharingAlgos.keyAlgos`, so preference order
    /// alone would pick the retired key and only status can send the active
    /// one to the ML-KEM entry.
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
      final retired =
          pkg.keys.singleWhere((k) => k.alg == SecretSharingAlgos.xWing);
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
      final rederived = await XWingPureDartAlgo.instance.keyPairFromSeed(seedA);
      expect(held.secretKey, rederived.secretKey);

      expect(registrant.heldKeyFor('not-a-kid-this-client-holds'), isNull);
    });

    test('a holding with nothing active refuses rather than picking one',
        () async {
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory();
      registrant.loadApkamKeys = () async => PersistedApkamKeys(encKeys: [
            PersistedEncKey(
                encSeed: base64Encode(seedA), status: KeyEntryStatus.retired),
          ]);

      await expectLater(
          registrant.register(),
          throwsA(isA<StateError>().having(
              (e) => '$e', 'message', contains('not one of them is active'))),
          reason: 'a retired key is retained to open what is in flight to it, '
              'not to be reached at — advertising one as the address would '
              'point every peer at a key this client has withdrawn');
    });

    test('and it names the statuses it actually found, not "retired"',
        () async {
      // NOTE: `status` is an open token, so reaching this throw proves "none
      // is active" and NOT "all are retired" — a holding carrying a revoked
      // key must not be described as merely superseded.
      final registrant = TestRegistrant(buildMockClient('enroll-a'))
        ..directory = FakeEnrollmentDirectory();
      registrant.loadApkamKeys = () async => PersistedApkamKeys(encKeys: [
            PersistedEncKey(
                encSeed: base64Encode(seedA),
                status: KeyEntryStatus.of('revoked')),
          ]);

      await expectLater(
          registrant.register(),
          throwsA(isA<StateError>()
              .having((e) => '$e', 'message', contains('"revoked"'))),
          reason: 'the diagnostic has to say what the holding actually is, or '
              'it sends a reader looking for a rotation that never happened');
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
        // NOTE: a package that names no suites is refused outright; this test
        // is about the entries.
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
          // NOTE: the retired one first, and under the stronger algorithm, so
          // selection has to lose to status rather than coincide with it.
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
      expect(pkg.bestKeyFor(SecretSharingAlgos.keyAlgos), isNull);
    });

    test('a package that names no suites is refused, not read as the oldest',
        () {
      // NOTE: an enrollment key package is write-once, so a default suite
      // would be permanent for the enrollment, and a holder cannot open what
      // arrives on a construction it never claimed.
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
        'suites': ['x-wing-hpke-v2', 'x-wing-hpke-v1', 7],
      }, enrollmentId: 'enroll-x');

      expect(pkg.suites, ['x-wing-hpke-v2', 'x-wing-hpke-v1'],
          reason: 'non-String entries are dropped the same way malformed key '
              'entries are, rather than throwing. Both survivors are now '
              'unknown to this build — one never existed, one was retired — '
              'and unknown is exactly what must be kept');
      expect(pkg.bestSuiteFor(['x-wing-hpke-v2', 'x-wing-hpke-v1']),
          'x-wing-hpke-v2',
          reason: 'the sender\'s order decides, strongest first');
      expect(pkg.bestSuiteFor(['x-wing-hpke-v1']), 'x-wing-hpke-v1');
    });

    test('no overlap is null rather than a guess', () {
      // NOTE: stamping the sender's own preference would hand the holder an
      // envelope it cannot unwrap, surfacing as an opaque AEAD error on the
      // far side rather than a refusal here.
      final pkg = KeyPackage.fromPayload({
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': <Object?>[],
        'suites': ['x-wing-hpke-v9'],
      }, enrollmentId: 'enroll-x');

      expect(pkg.bestSuiteFor(SecretSharingAlgos.suites), isNull);
    });

    test('what gets written declares what the advertised keys can open', () {
      // NOTE: the two arms differ in exactly one input — the KEM the
      // advertised key names — and no suite appears in both, so a `suites`
      // derived from the build's own list would answer identically for both.
      final xWingPayload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.xWing,
              pub: 'cA=='),
        ],
      );
      expect(xWingPayload['suites'], [SecretSharingAlgos.xWingRfc9180],
          reason: 'the advertisement names every construction an X-Wing '
              'private can open, and since the bespoke one was retired that '
              'is exactly the RFC 9180 suite');
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
      final payload =
          KeyPackage.payloadFor(createdAt: DateTime.utc(2026), keys: const []);
      expect(payload['suites'], isEmpty);
    });

    test('an unrecognised key algorithm contributes no suite', () {
      // NOTE: fails closed — a suite must not be claimed on a holder's behalf
      // from a key this build cannot identify, since the sender acts on the
      // claim and the failure lands on the holder.
      final payload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026),
        keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc,
              alg: 'kyber-1024-v9',
              pub: 'cA=='),
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

  /// A key package is an encapsulation target, so it is advertised as an
  /// APKAM-signed envelope and verified against the advertising enrollment's
  /// `_apsk` before the key inside is used.
  ///
  /// A package that does not verify drops that member alone: they are never
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
      // NOTE: resolve the secondary first — nesting the call inside `when`
      // would register the stub against getRemoteSecondary itself.
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

    /// The namespace-facts verb, beside the roster one and gated identically.
    ///
    /// `enroll:listns` answers with approved enrollments only, so a revoked
    /// enrollment leaves no trace on a roster and this is the only thing a
    /// client can ask to learn that one happened.
    group('lastRevokedAt', () {
      void stubInfons(AtClient atClient, String response) {
        final secondary = atClient.getRemoteSecondary()!;
        // NOTE: the command is the pin — a build that sent anything else
        // would find no stub here and throw.
        when(() =>
                secondary.executeCommand('enroll:infons:myapp\n', auth: true))
            .thenAnswer((_) async => response);
      }

      test('asks enroll:infons and parses the moment it answers with',
          () async {
        final atClient = buildMockClient('enroll-self');
        stubInfons(
            atClient, 'data:{"lastRevokedAt":"2026-03-04T05:06:07.008Z"}');

        final at =
            await VerbEnrollmentDirectory(atClient).lastRevokedAt('myapp');

        expect(at, DateTime.utc(2026, 3, 4, 5, 6, 7, 8));
        expect(at!.isUtc, isTrue,
            reason:
                'it is compared with the atServer\'s stamp on a record, and '
                'a local-time DateTime would compare wrongly by the offset');
      });

      test('a namespace nothing has been revoked in answers null', () async {
        final atClient = buildMockClient('enroll-self');
        stubInfons(atClient, 'data:{"lastRevokedAt":null}');

        expect(await VerbEnrollmentDirectory(atClient).lastRevokedAt('myapp'),
            isNull);
      });

      test(
          'an answer this build cannot read throws rather than reading as none',
          () async {
        // NOTE: null is "nothing was revoked", the answer that means do
        // nothing, so a shape nobody can read must not arrive as that.
        final atClient = buildMockClient('enroll-self');
        stubInfons(atClient, 'data:[]');

        await expectLater(
            VerbEnrollmentDirectory(atClient).lastRevokedAt('myapp'),
            throwsA(isA<AtValueException>()));
      });
    });

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

      expect(members.firstWhere((m) => m.enrollmentId == 'enroll-c').keyPackage,
          isNull);

      final excluded = await directory
          .listForNamespace('myapp', excludeEnrollmentIds: {'enroll-b'});
      expect(excluded.map((m) => m.enrollmentId), ['enroll-c']);
    });

    test('an unsigned key package is not sealed to', () async {
      final b = await registered('enroll-b');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', b.myKeyPackage.toJson())]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull,
          reason: 'accepting a bare package would leave the encapsulation '
              'target only as trustworthy as whatever served the record');
    });

    test('a key package signed by another enrollment is not sealed to',
        () async {
      // NOTE: accepting a package another enrollment signed would hand
      // enroll-d every secret meant for enroll-b.
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
      // NOTE: the claim inside the protected header matches the record —
      // envelope enrollmentId, record enrollmentId, all "enroll-b" — so every
      // structural check passes and only verification against enroll-b's real
      // _apsk catches it.
      final d = await registered('enroll-d');
      final forged = signEnvelope(d.myKeyPackage.toJson(),
          keys: [(await d.signingKeys).first],
          enrollmentId: 'enroll-b',
          type: EnvelopeType.keyPackage);
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', forged)]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull,
          reason: 'the claim is free to forge; the signature over it is not');
    });

    test('a tampered key package is not sealed to', () async {
      final b = await registered('enroll-b');
      // NOTE: the signature stays intact over the original body; only the
      // advertised key is swapped.
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
      // NOTE: registered so its own _apsk is published — the package below
      // must genuinely verify and then fail to PARSE, where one signed by
      // another enrollment would fail verification first.
      final future = await registered('enroll-future');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [
        record('enroll-b', await b.signedKeyPackagePayload()),
        record('enroll-none', null),
        record('enroll-wrong', await d.signedKeyPackagePayload()),
        record(
            'enroll-future',
            signEnvelope({'shape': 'from a later version'},
                keys: [(await future.signingKeys).first],
                enrollmentId: 'enroll-future',
                type: EnvelopeType.keyPackage)),
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

      expect(
          byId.values
              .where((m) => m.keyPackage != null)
              .map((m) => m.enrollmentId),
          ['enroll-b']);
    });

    test(
        'a package that names no enrollment still verifies — the record says '
        'whose it is', () async {
      // NOTE: the enroll:request shape is signed before the atServer assigns
      // an id, so there is nothing truthful to stamp; rejecting it would
      // refuse every key package that rides an enrollment request.
      final b = await registered('enroll-b');
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [
        record(
            'enroll-b',
            signEnvelope(b.myKeyPackage.toJson(),
                keys: [(await b.signingKeys).first],
                enrollmentId: null,
                type: EnvelopeType.keyPackage)),
      ]);

      final member =
          (await VerbEnrollmentDirectory(atClient).listForNamespace('myapp'))
              .single;

      expect(member.keyPackageStatus, KeyPackageStatus.present);
      expect(member.keyPackage!.enrollmentId, 'enroll-b',
          reason: 'injected from the record, which is where the id has always '
              'lived — the payload never carried it');
    });

    test('an envelope version this build cannot verify is rejected', () async {
      // NOTE: the version rides inside the protected header, so a later shape
      // cannot be checked at all — `rejected`, not the `unsupported` a merely
      // newer payload gets, which verified first.
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
      // NOTE: built through the raw JSON because the type refuses this at
      // parse; the property under test is one layer down.
      final signed = signEnvelope(b.myKeyPackage.toJson(),
          keys: [(await b.signingKeys).first],
          enrollmentId: 'enroll-b',
          type: EnvelopeType.keyPackage);
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
