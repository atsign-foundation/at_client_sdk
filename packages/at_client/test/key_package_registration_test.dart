import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

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

  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);

    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookupImpl();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
      remoteData[inv.positionalArguments[0].toString()] =
          inv.positionalArguments[1];
      return Future.value(true);
    });
    Future<AtValue> getFromRemoteData(Invocation inv) {
      final keyString = inv.positionalArguments[0].toString();
      final value = remoteData[keyString];
      if (value == null) {
        throw AtKeyNotFoundException('$keyString not found');
      }
      return Future.value(AtValue()..value = value);
    }

    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer(getFromRemoteData);
    when(() => atClient.get(any())).thenAnswer(getFromRemoteData);
    return atClient;
  }

  TestRegistrant buildRegistrant(
      String enrollmentId, FakeEnrollmentDirectory directory,
      {Uint8List? seed}) {
    final registrant = TestRegistrant(buildMockClient(enrollmentId))
      ..directory = directory;
    if (seed != null) {
      registrant.loadApkamKeys =
          () async => PersistedApkamKeys(xWingSeed: base64Encode(seed));
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
          registrant.publicSigningKey);

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
          .generateKeyPair(base64Decode(saved!.xWingSeed));
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
      }, enrollmentId: 'enroll-x', apkamId: 'apkam-x');
      expect(pkg.keys, hasLength(2));
      expect(pkg.enrollmentId, 'enroll-x');
      expect(pkg.apkamId, 'apkam-x');
      expect(pkg.bestKeyFor(['rsa-2048'])!.kid, 'k2');
      expect(pkg.bestKeyFor(['x-wing-99', 'rsa-2048'])!.kid, 'k1');
      expect(pkg.bestKeyFor(['something-else']), isNull);
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
          keys: [PackageKey(use: 'enc', alg: 'x-wing', pub: 'p')]);
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
      final forged = await d.signedKeyPackagePayload()
        ..['enrollmentId'] = 'enroll-b';
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', forged)]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull,
          reason: 'the claim is free to forge; the signature over it is not');
    });

    test('a tampered key package is not sealed to', () async {
      final b = await registered('enroll-b');
      final envelope = await b.signedKeyPackagePayload();
      // Signature intact over the original body; only the advertised key is
      // swapped, which is the substitution that matters.
      envelope['payload'] = {
        'v': 1,
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          {'kid': 'evil', 'use': 'enc', 'alg': 'x-wing', 'pub': 'evil-pub'}
        ],
      };
      final atClient = buildMockClient('enroll-self');
      stubListns(atClient, [record('enroll-b', envelope)]);

      final members =
          await VerbEnrollmentDirectory(atClient).listForNamespace('myapp');

      expect(members.single.keyPackage, isNull);
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
