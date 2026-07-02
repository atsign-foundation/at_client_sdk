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

  group('VerbEnrollmentDirectory', () {
    test(
        'listForNamespace parses members + per-APKAM key packages and honours '
        'exclude', () async {
      final atClient = buildMockClient('enroll-self');
      final secondary = atClient.getRemoteSecondary()!;
      // Flat 1:1:1 shape: one record per enrollment, no nested apkam[] array;
      // apkamPubKey + metadata sit directly on the record.
      final response = jsonEncode([
        {
          'enrollmentId': 'enroll-b',
          'access': 'rw',
          'apkamPubKey': 'pkb',
          'metadata': {
            'keyPackage': {
              'v': 1,
              'createdAt': '2026-06-11T00:00:00.000Z',
              'keys': [
                {'kid': 'kb', 'use': 'enc', 'alg': 'x-wing', 'pub': 'pubb'}
              ],
            }
          }
        },
        {
          'enrollmentId': 'enroll-c',
          'access': 'r',
          'apkamPubKey': 'pkc',
          'metadata': {}
        },
      ]);
      when(() => secondary.executeCommand('enroll:listns:myapp\n', auth: true))
          .thenAnswer((_) async => 'data:$response');

      final directory = VerbEnrollmentDirectory(atClient);
      final members = await directory.listForNamespace('myapp');
      expect(
          members.map((m) => m.enrollmentId).toSet(), {'enroll-b', 'enroll-c'});
      final b = members.firstWhere((m) => m.enrollmentId == 'enroll-b');
      expect(b.access, 'rw');
      expect(b.keyPackage, isNotNull);
      // apkamId is populated from the record's apkamPubKey
      expect(b.keyPackage!.apkamId, 'pkb');
      expect(
          b.keyPackage!.bestKeyFor(SecretSharingAlgos.keyAlgos)!.pub, 'pubb');
      final c = members.firstWhere((m) => m.enrollmentId == 'enroll-c');
      expect(c.keyPackage, isNull);

      final excluded = await directory
          .listForNamespace('myapp', excludeEnrollmentIds: {'enroll-b'});
      expect(excluded.map((m) => m.enrollmentId), ['enroll-c']);
    });
  });
}
