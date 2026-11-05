import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show CryptographicMaterialRole;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/test_keypairs.dart';
import 'test_utils/ml_dsa_keyfile.dart' show keysHoldingApkam;
import 'test_utils/nskey_generation.dart';

/// A bare mock, shadowing the shared one whose concrete `getPreferences()`
/// cannot be stubbed.
class MockAtClient extends Mock implements AtClient {}

class _Unprivileged implements EnrollmentPrivilegeResolver {
  @override
  Future<bool> isFullyPrivileged() async => false;
  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async => false;
}

/// An nskey private arriving at a client is checked against the generation
/// its atSign published, by the filing the client actually builds.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  /// A client that publishes `public:__nskey.<ns>@alice` to an in-memory
  /// atServer and serves it back, with every `_apsk` answering the key that
  /// signed it, and minting ML-KEM-1024 only.
  MockAtClient client() {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookUp();
    final local = MockLocalSecondary();
    final advertised = <String, String>{};
    final pair = pkamKeyPairFor(atSign, 'enroll-a');
    when(() => local.getPkamPublicKey())
        .thenAnswer((_) async => pair.atPublicKey.publicKey);
    when(() => local.getPkamPrivateKey())
        .thenAnswer((_) async => pair.atPrivateKey.privateKey);

    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn('enroll-a');
    when(() => atClient.atKeysIo).thenAnswer(
        (_) => keysHoldingApkam(atSign, atClient.enrollmentId, pair));
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
        keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]));
    when(() => atClient.dataEvents)
        .thenAnswer((_) => const Stream<DataEvent>.empty());
    when(() => atClient.getLocalSecondary()).thenReturn(local);
    when(() => local.executeVerb(any(),
            cameFromServer: any(named: 'cameFromServer')))
        .thenAnswer((_) async => 'data:1');
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => secondary.executeCommand(any(that: startsWith('enroll:listns')),
        auth: any(named: 'auth'))).thenAnswer((_) async => 'data:[]');
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      if (key.key != '__nskey') {
        return AtValue()..value = pair.atPublicKey.publicKey;
      }
      final serving = advertised[key.namespace];
      if (serving == null) throw AtKeyNotFoundException('$key');
      return AtValue()..value = serving;
    });
    when(() => secondary.executeVerb(any())).thenAnswer((inv) async {
      final builder = inv.positionalArguments[0];
      if (builder is UpdateVerbBuilder && builder.atKey.key == '__nskey') {
        advertised[builder.atKey.namespace!] = builder.value as String;
      }
      return 'data:1';
    });
    return atClient;
  }

  Future<InMemoryAtKeysIo> emptyKeys() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return io;
  }

  /// Publishes an ML-KEM-1024 generation for [namespace] and returns its kid
  /// and seed, as another enrollment would convey them.
  Future<({String kid, String seed})> published(MockAtClient c) async {
    final minterFiling =
        NskeyPrivateFiling(keysIo: await emptyKeys(), atSign: atSign);
    final advertisement =
        await PublishedNskeyKeyRing(c, privateFiling: minterFiling)
            .mintAndPublish(namespace);
    final kid = advertisement.nskeyKid;
    final seed = await minterFiling.readSeed(namespace, kid);
    return (kid: kid, seed: base64Encode(seed!.bytes));
  }

  /// [seed] as it arrives, conveyed under [kid].
  Secret conveyedAs(String kid, Uint8List seed) => Secret(
      namespace: namespace,
      name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
      value: base64Encode(seed));

  /// The filings a client builds that an arriving private reaches, each over
  /// [keys] as the client's key source.
  final builders =
      <String, NskeyPrivateFiling Function(MockAtClient c, AtKeysIo keys)>{
    'the start-up bootstrap\'s': (c, keys) => PqClientBootstrap(c,
        keysIo: keys,
        privilege: _Unprivileged(),
        sweepUnanchoredEnrollments: () async => 0).filing!,
    'a key ring\'s own': (c, keys) {
      when(() => c.atKeysIo).thenReturn(keys);
      return PublishedNskeyKeyRing(c).privateFiling!;
    },
    'a rotation\'s': (c, keys) {
      when(() => c.atKeysIo).thenReturn(keys);
      return NskeyRotation.forClient(c).privateFiling;
    },
  };

  for (final MapEntry(key: whose, value: build) in builders.entries) {
    group('$whose filing', () {
      test('files an arriving private under its KEM', () async {
        final c = client();
        final conveyed = await published(c);
        final keys = await emptyKeys();
        final filing = build(c, keys);

        final stored = await filing.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}${conveyed.kid}',
            value: conveyed.seed));

        expect(stored, isTrue);
        final material = (await keys.read(atSign)).getAtSignKey(
            NskeyPrivateFiling.keyIdFor(namespace, conveyed.kid),
            CryptographicMaterialRole.privateDecapsulation);
        expect(SecretSharingAlgos.keyAlgoForMaterial(material!.algorithm),
            SecretSharingAlgos.mlKem1024,
            reason: 'a seed filed under X-Wing is expanded as X-Wing, and the '
                'namespace cannot be opened');
        expect(await filing.read(namespace, conveyed.kid), isNotNull);
      });

      test(
          'files an earlier generation\'s private, its kid no longer '
          'published, under the KEM its seed names', () async {
        final c = client();
        await published(c);
        final keys = await emptyKeys();
        final filing = build(c, keys);
        final earlier = await nskeyGeneration(SecretSharingAlgos.mlKem1024);

        final stored = await filing.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}${earlier.kid}',
            value: base64Encode(earlier.seed)));

        expect(stored, isTrue);
        final material = (await keys.read(atSign)).getAtSignKey(
            NskeyPrivateFiling.keyIdFor(namespace, earlier.kid),
            CryptographicMaterialRole.privateDecapsulation);
        expect(SecretSharingAlgos.keyAlgoForMaterial(material!.algorithm),
            SecretSharingAlgos.mlKem1024);
      });

      test('refuses an arriving private that does not derive the published key',
          () async {
        final c = client();
        final conveyed = await published(c);
        final keys = await emptyKeys();
        final filing = build(c, keys);
        final wrong = Uint8List.fromList(
            List<int>.generate(64, (_) => Random.secure().nextInt(256)));

        final stored = await filing.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}${conveyed.kid}',
            value: base64Encode(wrong)));

        expect(stored, isFalse,
            reason: 'a private that opens nothing peers seal to would leave '
                'this client believing it can read the namespace');
        expect(await filing.readSeed(namespace, conveyed.kid), isNull);
      });

      test(
          'with nothing published under its kid, refuses a private whose seed '
          'derives another kid, and files the real one after it', () async {
        final c = client();
        final keys = await emptyKeys();
        final filing = build(c, keys);
        final generation = await nskeyGeneration(SecretSharingAlgos.mlKem1024);
        final wrong = Uint8List.fromList(
            List<int>.generate(64, (_) => Random.secure().nextInt(256)));

        expect(await filing.file(conveyedAs(generation.kid, wrong)), isFalse,
            reason: 'nothing is published yet, and the seed is not the '
                'generation its kid names');
        expect(await filing.file(conveyedAs(generation.kid, generation.seed)),
            isTrue,
            reason: 'the refusal kept nothing, so the real private files');
        expect((await filing.readSeed(namespace, generation.kid))!.bytes,
            generation.seed);
      });

      test(
          'with nothing published under its kid, refuses a seed of one KEM '
          'filed under the kid of another', () async {
        final c = client();
        final filing = build(c, await emptyKeys());
        final mlKem = await nskeyGeneration(SecretSharingAlgos.mlKem1024);
        final xWing = await nskeyGeneration(SecretSharingAlgos.xWing);

        expect(await filing.file(conveyedAs(mlKem.kid, xWing.seed)), isFalse);
        expect(await filing.file(conveyedAs(xWing.kid, xWing.seed)), isTrue,
            reason: 'the control: the same seed files under its own kid');
      });
    });
  }

  test(
      'after a refused seed and the real one filed before the publish, an own '
      'write seals to the real public half', () async {
    final c = client();
    final keys = await emptyKeys();
    when(() => c.atKeysIo).thenReturn(keys);
    final ring = PublishedNskeyKeyRing(c);
    final generation = await nskeyGeneration(SecretSharingAlgos.mlKem1024);
    final wrong = Uint8List.fromList(
        List<int>.generate(64, (_) => Random.secure().nextInt(256)));

    expect(await ring.privateFiling!.file(conveyedAs(generation.kid, wrong)),
        isFalse);
    expect(
        await ring.privateFiling!
            .file(conveyedAs(generation.kid, generation.seed)),
        isTrue);

    final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
    final real = (await kem.keyPairFromSeed(generation.seed)).publicKey;
    final held = await ring.heldPublic(atSign, namespace, generation.kid);
    expect(held?.pubBytes, real,
        reason: 'an own write seals to the public half the held private '
            'derives, which is the real generation\'s');
  });
}
