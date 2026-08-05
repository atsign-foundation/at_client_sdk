import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {
  // The real spec getter has a concrete rsa2048 default; `implements` erases
  // it, and an unstubbed mocktail getter returns null into a non-nullable.
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class MockPairwiseSecretSharing extends Mock implements PairwiseSecretSharing {}

/// The nskey-private self-heal: mint if none exists, else pull from any
/// current holder (`decisions.md` 38).
///
/// What forced this: the only delivery of an nskey private was the mint-time
/// push, so any enrollment created after the mint was stranded — it met
/// `no nskey private held` with no request, no retry and no recovery, and
/// that is the ordinary second device, not an edge case. These tests pin the
/// two pull triggers (start-time sweep, on-miss read) and the shape of the
/// ask, so the healing loop can never again silently lose its initiator.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(Duration.zero);
  });

  late XWingKeyPair pair;

  setUpAll(() async => pair = await XWingKeyPair.generate());

  /// A client whose enrollment can name its namespaces via the preference —
  /// the legacy-PKAM shape, which is most of the fleet during the rollout.
  MockAtClient client() {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookupImpl();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => lookUp.enrollmentId).thenReturn(null);
    when(() => atClient.getPreferences())
        .thenReturn(AtClientPreference()..namespace = namespace);
    return atClient;
  }

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: atSign);
  }

  group('the start-time pull (NskeySeeding.requestMissingPrivates)', () {
    test('asks for a published generation this client does not hold', () async {
      final atClient = client();
      final ring =
          PublishedNskeyKeyRing(atClient, privateFiling: await filing());
      final kid = nskeyKidOf(pair.publicKeyBytes);
      ring.rememberOwn(
          atSign, namespace, (nskeyKid: kid, publicKey: pair.publicKeyBytes));

      final sharing = MockPairwiseSecretSharing();
      when(() => sharing.requestSecretsFromNamespace(any(),
          names: any(named: 'names'))).thenAnswer((_) async => 2);
      when(() => sharing.waitForSecret(any(), any(),
              timeout: any(named: 'timeout')))
          .thenAnswer((_) => Completer<Secret>().future);

      final seeding = NskeySeeding(
          atClient: atClient, ring: ring, privateFiling: ring.privateFiling);

      expect(await seeding.requestMissingPrivates(sharing), {namespace});
      final captured = verify(() => sharing.requestSecretsFromNamespace(
          namespace,
          names: captureAny(named: 'names'))).captured.single as List<String>;
      expect(captured, ['${NskeyPrivateFiling.secretNamePrefix}$kid'],
          reason: 'the ask names the exact generation, so a holder with '
              'several after a rotation serves the one peers are sealing to');
    });

    test('does not ask when the private is already held', () async {
      final atClient = client();
      final held = await filing();
      final kid = nskeyKidOf(pair.publicKeyBytes);
      await held.store(
          namespace: namespace, nskeyKid: kid, private: pair.privateKeyBytes);
      final ring = PublishedNskeyKeyRing(atClient, privateFiling: held);
      ring.rememberOwn(
          atSign, namespace, (nskeyKid: kid, publicKey: pair.publicKeyBytes));

      final sharing = MockPairwiseSecretSharing();

      expect(
          await NskeySeeding(
                  atClient: atClient, ring: ring, privateFiling: held)
              .requestMissingPrivates(sharing),
          isEmpty,
          reason: 'a client that holds the current generation has nothing to '
              'heal, and asking anyway would put a broadcast on every start');
      verifyNever(() => sharing.requestSecretsFromNamespace(any(),
          names: any(named: 'names')));
    });

    test('does not ask on cold start — minting\'s business, not pulling\'s',
        () async {
      final atClient = client();
      final ring =
          PublishedNskeyKeyRing(atClient, privateFiling: await filing());
      final sharing = MockPairwiseSecretSharing();

      expect(
          await NskeySeeding(
                  atClient: atClient,
                  ring: ring,
                  privateFiling: ring.privateFiling)
              .requestMissingPrivates(sharing),
          isEmpty);
      verifyNever(() => sharing.requestSecretsFromNamespace(any(),
          names: any(named: 'names')));
    });

    test(
        'files the answer the moment it arrives, so the heal completes '
        'within this run', () async {
      final atClient = client();
      final fileStore = await filing();
      final ring = PublishedNskeyKeyRing(atClient, privateFiling: fileStore);
      final kid = nskeyKidOf(pair.publicKeyBytes);
      ring.rememberOwn(
          atSign, namespace, (nskeyKid: kid, publicKey: pair.publicKeyBytes));

      final sharing = MockPairwiseSecretSharing();
      when(() => sharing.requestSecretsFromNamespace(any(),
          names: any(named: 'names'))).thenAnswer((_) async => 1);
      final answer = Secret(
        namespace: namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
        value: base64Encode(pair.privateKeyBytes),
      );
      when(() => sharing.waitForSecret(any(), any(),
          timeout: any(named: 'timeout'))).thenAnswer((_) async => answer);

      await NskeySeeding(
              atClient: atClient, ring: ring, privateFiling: fileStore)
          .requestMissingPrivates(sharing);
      // The filing is unawaited by design; give the microtask queue a turn.
      await Future<void>.delayed(Duration.zero);

      expect(await fileStore.read(namespace, kid), pair.privateKeyBytes,
          reason: 'an answer arriving mid-run must be filed now, not at the '
              'next start — otherwise the heal needs a restart the user has '
              'no reason to perform');
      expect(await ring.privateHalf(atSign, namespace, kid), isNotNull,
          reason: 'and the ring must serve it, which is what actually makes '
              'the namespace readable');
    });

    test('a client with nowhere to file the answer does not ask', () async {
      final atClient = client();
      final ring = PublishedNskeyKeyRing(atClient);
      final kid = nskeyKidOf(pair.publicKeyBytes);
      ring.rememberOwn(
          atSign, namespace, (nskeyKid: kid, publicKey: pair.publicKeyBytes));
      final sharing = MockPairwiseSecretSharing();

      expect(
          await NskeySeeding(atClient: atClient, ring: ring)
              .requestMissingPrivates(sharing),
          isEmpty,
          reason: 'an answer that cannot be filed durably is an answer lost '
              'on restart — asking for it would spend a broadcast on nothing');
    });
  });

  group('the on-miss pull (PublishedNskeyKeyRing)', () {
    test('a miss on an own generation fires the injected ask, once', () async {
      final atClient = client();
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(
        atClient,
        privateFiling: await filing(),
        requestConveyance: (ns, name) async => asked.add((ns, name)),
      );

      expect(await ring.privateHalf(atSign, namespace, 'kid1'), isNull);
      expect(await ring.privateHalf(atSign, namespace, 'kid1'), isNull);
      await Future<void>.delayed(Duration.zero);

      expect(asked, [(namespace, '${NskeyPrivateFiling.secretNamePrefix}kid1')],
          reason: 'a synced backlog fails through here in a burst, and N '
              'identical broadcasts buy nothing the first did not');
    });

    test('a miss on a PEER\'s generation never asks', () async {
      final atClient = client();
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(
        atClient,
        requestConveyance: (ns, name) async => asked.add((ns, name)),
      );

      expect(await ring.privateHalf('@bob', namespace, 'kid1'), isNull);
      await Future<void>.delayed(Duration.zero);

      expect(asked, isEmpty,
          reason: 'only this atSign\'s own privates are ever conveyed to it — '
              'asking our enrollments for @bob\'s private is a request nothing '
              'may ever answer');
    });

    test('a hit never asks', () async {
      final atClient = client();
      final held = await filing();
      final kid = nskeyKidOf(pair.publicKeyBytes);
      await held.store(
          namespace: namespace, nskeyKid: kid, private: pair.privateKeyBytes);
      final asked = <(String, String)>[];
      final ring = PublishedNskeyKeyRing(
        atClient,
        privateFiling: held,
        requestConveyance: (ns, name) async => asked.add((ns, name)),
      );

      expect(await ring.privateHalf(atSign, namespace, kid), isNotNull);
      await Future<void>.delayed(Duration.zero);

      expect(asked, isEmpty);
    });
  });
}
