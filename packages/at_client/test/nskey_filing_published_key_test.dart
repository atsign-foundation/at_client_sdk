// The minting side of this fixture signs from an AtChops, the shape a client
// with no key source has.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show CryptographicMaterialRole;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/test_keypairs.dart';

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
    final chops = AtChopsImpl(AtChopsKeys.create(
        null,
        AtPkamKeyPair.create(
            pair.atPublicKey.publicKey, pair.atPrivateKey.privateKey)));

    when(() => atClient.atChops).thenReturn(chops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn('enroll-a');
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
        return AtValue()
          ..value = chops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;
      }
      final serving = advertised[key.namespace];
      if (serving == null) throw AtKeyNotFoundException('$key');
      return AtValue()..value = serving;
    });
    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
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
      test('files an arriving private under the KEM its generation names',
          () async {
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
        final earlier = Uint8List.fromList(
            List<int>.generate(64, (_) => Random.secure().nextInt(256)));

        final stored = await filing.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}kid-earlier',
            value: base64Encode(earlier)));

        expect(stored, isTrue);
        final material = (await keys.read(atSign)).getAtSignKey(
            NskeyPrivateFiling.keyIdFor(namespace, 'kid-earlier'),
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
    });
  }
}
