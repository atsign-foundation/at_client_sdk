import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class TestRegistrant
    with ApkamSigning, EnvelopeSigning, PairwiseClientRegistration {
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

  /// Simulates the remote atServer's keystore: full key string -> value.
  /// All mocked clients read and write this map, so what one client
  /// publishes another can discover.
  late Map<String, String> remoteData;

  // A deterministic X-Wing seed for tests that want a stable identity,
  // injected via loadClientKeys.
  final Uint8List clientSeedA =
      Uint8List.fromList(List<int>.generate(32, (i) => i));
  late Uint8List clientPublicKeyA;

  setUpAll(() async {
    registerFallbackValue(AtKey());
    clientPublicKeyA =
        (await XWingPureDartAlgo.instance.generateKeyPair(clientSeedA))
            .publicKey;
  });

  /// Wires up a mock AtClient whose put/get/getAtKeys/delete operate on
  /// [remoteData], with a real AtChops holding a fresh PKAM keypair.
  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = MockAtClient();
    final atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);

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
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((inv) {
      final keyString = inv.positionalArguments[0].toString();
      final value = remoteData[keyString];
      if (value == null) {
        throw AtKeyNotFoundException('$keyString not found');
      }
      return Future.value(AtValue()..value = value);
    });
    when(() => atClient.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      final showHidden = inv.namedArguments[#showHiddenKeys] == true;
      return Future.value(remoteData.keys
          .where((k) => regex.hasMatch(k))
          // model the server: hidden public keys need showhidden:true
          .where((k) => showHidden || !k.startsWith('public:_'))
          .map(AtKey.fromString)
          .toList());
    });
    when(() => atClient.delete(any(),
        deleteRequestOptions: any(named: 'deleteRequestOptions'))).thenAnswer(
      (inv) {
        remoteData.remove(inv.positionalArguments[0].toString());
        return Future.value(true);
      },
    );
    return atClient;
  }

  /// A registrant whose identity is stable (injected) rather than generated.
  TestRegistrant buildRegistrant(String enrollmentId,
      {String? stableClientId}) {
    final registrant = TestRegistrant(buildMockClient(enrollmentId));
    if (stableClientId != null) {
      registrant.loadClientKeys = () async => PersistedClientKeys(
            clientId: stableClientId,
            xWingSeed: base64Encode(clientSeedA),
          );
    }
    return registrant;
  }

  setUp(() {
    remoteData = {};
  });

  group('registerClient', () {
    test('publishes _apsk key and a signed bundle at the expected key',
        () async {
      final registrant = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      final bundle = await registrant.registerClient();
      await registrant.deregisterClient(); // stop the republish timer

      expect(bundle.clientId, 'cid-a');
      expect(bundle.enrollmentId, 'enroll-a');

      // _apsk was published
      expect(remoteData['public:_apsk.enroll-a.a.__e$atSign'],
          registrant.publicSigningKey);

      // bundle was published at the hidden-public per-enrollment key, then
      // removed again by deregisterClient
      final bundleKeyUri = 'public:__sskb-cid-a.enroll-a.a.__e$atSign';
      expect(remoteData.containsKey(bundleKeyUri), isFalse);
    });

    test('published bundle is a verifiable envelope with an x-wing enc key',
        () async {
      final registrant = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrant.registerClient();
      await registrant.deregisterClient();
      // re-publish without the timer to inspect the stored value
      registrant.keyPackageTtl = Duration(hours: 12);
      await registrant.registerClient();
      await registrant.deregisterClient();

      final captured = verify(() => registrant.atClient.put(
          captureAny(), captureAny(),
          putRequestOptions: any(named: 'putRequestOptions'))).captured;
      // puts: _apsk (once - second registerClient finds it), bundle, bundle
      final bundlePuts = <(AtKey, String)>[];
      for (var i = 0; i < captured.length; i += 2) {
        final key = captured[i] as AtKey;
        if (key.toString().contains('__sskb-')) {
          bundlePuts.add((key, captured[i + 1] as String));
        }
      }
      expect(bundlePuts, hasLength(2));

      final (atKey, value) = bundlePuts.last;
      expect(atKey.metadata.ttl, Duration(hours: 12).inMilliseconds);

      final envelope = jsonDecode(value) as Map;
      expect(envelope['enrollmentId'], 'enroll-a');
      final parsed = ClientKeyPackage.fromJson(envelope['payload']);
      expect(parsed.v, ClientKeyPackage.currentVersion);
      final key = parsed.bestKeyFor(SecretSharingAlgos.keyAlgos);
      expect(key, isNotNull);
      expect(key!.alg, SecretSharingAlgos.xWing);
      expect(key.use, SecretSharingAlgos.useEnc);
      expect(key.pub, base64Encode(clientPublicKeyA));
      expect(key.kid, PackageKey.computeKid(key.pub));
    });

    test('generates and saves a fresh identity when no loader is supplied',
        () async {
      final registrant = TestRegistrant(buildMockClient('enroll-a'));
      PersistedClientKeys? saved;
      registrant.saveClientKeys = (keys) async => saved = keys;

      final bundle = await registrant.registerClient();
      await registrant.deregisterClient();

      expect(saved, isNotNull);
      expect(saved!.clientId, bundle.clientId);
      // the persisted seed deterministically re-derives the published key
      final rederived = await XWingPureDartAlgo.instance
          .generateKeyPair(base64Decode(saved!.xWingSeed));
      expect(base64Encode(rederived.publicKey),
          bundle.bestKeyFor(SecretSharingAlgos.keyAlgos)!.pub);
    });
  });

  group('discoverClients', () {
    test('B discovers and verifies A\'s bundle; own bundle is excluded',
        () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient();

      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient();

      final seenByB = await registrantB.discoverClients();
      expect(seenByB, hasLength(1));
      expect(seenByB.single.clientId, 'cid-a');
      expect(seenByB.single.enrollmentId, 'enroll-a');

      final seenByA = await registrantA.discoverClients();
      expect(seenByA.single.clientId, 'cid-b');

      // filter by enrollmentId
      final onlyEnrollB =
          await registrantA.discoverClients(enrollmentId: 'enroll-b');
      expect(onlyEnrollB.single.clientId, 'cid-b');
      final onlyEnrollC =
          await registrantA.discoverClients(enrollmentId: 'enroll-c');
      expect(onlyEnrollC, isEmpty);

      await registrantA.deregisterClient();
      await registrantB.deregisterClient();
    });

    test('excludeEnrollmentIds drops packages from those enrollments',
        () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient();
      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient();
      final registrantC = buildRegistrant('enroll-c', stableClientId: 'cid-c');
      await registrantC.registerClient();

      // A sees both B and C with no exclusion.
      final all = await registrantA.discoverClients();
      expect(all.map((p) => p.enrollmentId).toSet(), {'enroll-b', 'enroll-c'});

      // Excluding enroll-b (a revocation) leaves only C.
      final excludingB =
          await registrantA.discoverClients(excludeEnrollmentIds: {'enroll-b'});
      expect(excludingB.map((p) => p.enrollmentId).toSet(), {'enroll-c'});

      // Excluding both leaves nothing to distribute to.
      final excludingBoth = await registrantA
          .discoverClients(excludeEnrollmentIds: {'enroll-b', 'enroll-c'});
      expect(excludingBoth, isEmpty);

      await registrantA.deregisterClient();
      await registrantB.deregisterClient();
      await registrantC.deregisterClient();
    });

    test('a bundle with a tampered payload is skipped', () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient();

      final bundleKeyUri = 'public:__sskb-cid-a.enroll-a.a.__e$atSign';
      final envelope = jsonDecode(remoteData[bundleKeyUri]!) as Map;
      (envelope['payload'] as Map)['clientId'] = 'cid-evil';
      remoteData[bundleKeyUri] = jsonEncode(envelope);

      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient();
      await registrantB.deregisterClient();

      final seenByB = await registrantB.discoverClients();
      expect(seenByB, isEmpty);
      await registrantA.deregisterClient();
    });

    test(
        'a validly-signed bundle planted under a different enrollment\'s '
        'key location is skipped', () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient();

      // Move A's (validly signed) bundle to a key location claiming
      // enrollment enroll-x. On a real atServer enroll-a could not write
      // there, but defence in depth: the location/claim binding check.
      final bundleKeyUri = 'public:__sskb-cid-a.enroll-a.a.__e$atSign';
      final plantedUri = 'public:__sskb-cid-a.enroll-x.a.__e$atSign';
      remoteData[plantedUri] = remoteData.remove(bundleKeyUri)!;

      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient();
      await registrantB.deregisterClient();

      expect(await registrantB.discoverClients(), isEmpty);
      await registrantA.deregisterClient();
    });
  });

  group('ClientKeyPackage parsing', () {
    test(
        'unknown-alg entries are kept, malformed entries are skipped, '
        'bestKeyFor honours preference order', () {
      final json = {
        'v': 1,
        'clientId': 'cid-x',
        'enrollmentId': 'enroll-x',
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [
          {'kid': 'k1', 'use': 'enc', 'alg': 'x-wing-99', 'pub': 'future-pub'},
          {'kid': 'k2', 'use': 'enc', 'alg': 'rsa-2048', 'pub': 'rsa-pub'},
          {'kid': 'k3', 'use': 'enc'}, // malformed: no alg/pub
          'not even a map',
        ],
      };
      final bundle = ClientKeyPackage.fromJson(json);
      expect(bundle.keys, hasLength(2));

      // this client doesn't know x-wing-99: rsa is chosen
      expect(bundle.bestKeyFor(['rsa-2048'])!.kid, 'k2');
      // a future client preferring x-wing-99 picks it first
      expect(bundle.bestKeyFor(['x-wing-99', 'rsa-2048'])!.kid, 'k1');
      // no common algorithm
      expect(bundle.bestKeyFor(['something-else']), isNull);
    });

    test('malformed bundle throws FormatException', () {
      expect(() => ClientKeyPackage.fromJson({'v': 'one'}),
          throwsA(isA<FormatException>()));
      expect(() => ClientKeyPackage.fromJson('a string'),
          throwsA(isA<FormatException>()));
    });

    test('a bundle without a namespaces field (older writer) parses as []', () {
      final bundle = ClientKeyPackage.fromJson({
        'v': 1,
        'clientId': 'cid-x',
        'enrollmentId': 'enroll-x',
        'createdAt': '2026-06-11T00:00:00.000Z',
        'keys': [],
      });
      expect(bundle.namespaces, isEmpty);
    });
  });

  group('namespace-scoped registration and discovery', () {
    test(
        'registerClient publishes a cleartext self-key copy per namespace, '
        'carrying the signed namespace list; deregister removes them',
        () async {
      final registrant = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      final bundle = await registrant
          .registerClient(namespaces: ['myapp', 'examples.demos']);

      expect(bundle.namespaces, ['examples.demos', 'myapp']); // sorted

      final copyMyapp = 'sskb-cid-a.enroll-a.__sskbns.myapp$atSign';
      final copyDemos = 'sskb-cid-a.enroll-a.__sskbns.examples.demos$atSign';
      expect(remoteData.containsKey(copyMyapp), isTrue);
      expect(remoteData.containsKey(copyDemos), isTrue);
      // copies carry the same signed envelope as the canonical bundle
      expect(remoteData[copyMyapp],
          remoteData['public:__sskb-cid-a.enroll-a.a.__e$atSign']);
      // raw JSON (never whole-value base64)
      expect(remoteData[copyMyapp]!.startsWith('{'), isTrue);

      await registrant.deregisterClient();
      expect(remoteData.containsKey(copyMyapp), isFalse);
      expect(remoteData.containsKey(copyDemos), isFalse);
    });

    test(
        'discoverClients(namespace:) returns only clients registered for '
        'that namespace, excluding self', () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient(namespaces: ['myapp']);

      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient(namespaces: ['myapp', 'mychat']);

      final registrantC = buildRegistrant('enroll-c', stableClientId: 'cid-c');
      await registrantC.registerClient(); // no namespaces

      final seenByA = await registrantA.discoverClients(namespace: 'myapp');
      expect(seenByA.map((b) => b.clientId), ['cid-b']); // not self, not C

      final chatOnly = await registrantA.discoverClients(namespace: 'mychat');
      expect(chatOnly.map((b) => b.clientId), ['cid-b']);

      // global discovery still sees everyone
      final global = await registrantA.discoverClients();
      expect(global.map((b) => b.clientId).toSet(), {'cid-b', 'cid-c'});

      await registrantA.deregisterClient();
      await registrantB.deregisterClient();
      await registrantC.deregisterClient();
    });

    test(
        'a genuine signed bundle planted under a namespace outside its '
        'signed namespace list is rejected', () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient(namespaces: ['myapp']);

      // an owner-class actor copies A's genuine bundle copy into a
      // namespace A did not register for (on a real atServer only a
      // wildcard/legacy connection could do this write)
      remoteData['sskb-cid-a.enroll-a.__sskbns.banking$atSign'] =
          remoteData['sskb-cid-a.enroll-a.__sskbns.myapp$atSign']!;

      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient();

      expect(await registrantB.discoverClients(namespace: 'banking'), isEmpty);
      // the legitimate copy still discovers fine
      expect(
          (await registrantB.discoverClients(namespace: 'myapp'))
              .map((b) => b.clientId),
          ['cid-a']);

      await registrantA.deregisterClient();
      await registrantB.deregisterClient();
    });

    test('discoverClients(namespace:, enrollmentId:) combines both filters',
        () async {
      final registrantA = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrantA.registerClient(namespaces: ['myapp']);
      final registrantB = buildRegistrant('enroll-b', stableClientId: 'cid-b');
      await registrantB.registerClient(namespaces: ['myapp']);

      final registrantC = buildRegistrant('enroll-c', stableClientId: 'cid-c');
      await registrantC.registerClient();

      final found = await registrantC.discoverClients(
          namespace: 'myapp', enrollmentId: 'enroll-b');
      expect(found.map((b) => b.clientId), ['cid-b']);

      await registrantA.deregisterClient();
      await registrantB.deregisterClient();
      await registrantC.deregisterClient();
    });

    test(
        'registerClient namespaces are additive across calls; deregister '
        'clears them', () async {
      final registrant = buildRegistrant('enroll-a', stableClientId: 'cid-a');
      await registrant.registerClient(namespaces: ['myapp']);
      // a second consumer of the same instance declares its own namespace
      final bundle = await registrant.registerClient(namespaces: ['mychat']);

      expect(registrant.registeredNamespaces, {'myapp', 'mychat'});
      expect(bundle.namespaces, ['myapp', 'mychat']); // union, sorted
      expect(
          remoteData.containsKey('sskb-cid-a.enroll-a.__sskbns.myapp$atSign'),
          isTrue,
          reason: 'first consumer\'s copy must survive the second call');
      expect(
          remoteData.containsKey('sskb-cid-a.enroll-a.__sskbns.mychat$atSign'),
          isTrue);

      await registrant.deregisterClient();
      expect(registrant.registeredNamespaces, isEmpty);
      expect(remoteData.keys.where((k) => k.contains('.__sskbns.')), isEmpty);
    });
  });
}
