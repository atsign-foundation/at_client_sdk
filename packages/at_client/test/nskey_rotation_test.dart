import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart'
    show NskeySeeding;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientEnvelopeSigner;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

class MockAtClient extends Mock implements AtClient {}

class MockSharing extends Mock implements PairwiseSecretSharing {}

class FakeSecret extends Fake implements Secret {}

class FakeEnrollmentRequestDecision extends Fake
    implements EnrollmentRequestDecision {}

/// The nskey-keypair rotation lever (design.md §1.7 B5b) and the revocation it
/// composes with (B6).
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  final logs = RecordedLogs();

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
    registerFallbackValue(FakeSecret());
    registerFallbackValue(FakeEnrollmentRequestDecision());
    logs.installOn();
  });

  /// A client whose remote verbs succeed, recording an ordered trace of what
  /// it was asked to do, and serving back whatever has been published.
  /// [lockAlreadyHeld] makes the mint lock's immutable create fail, which is
  /// how the atServer reports that another enrollment holds it.
  ///
  /// The mint and rotate paths read the atServer rather than this client's
  /// caches — a sibling enrollment's publication is not in local storage until
  /// sync catches up — so the fixture has to hold the record for them to find.
  ({
    MockAtClient client,
    List<String> trace,
    List<String> published,
    Map<String, String> advertised,
    void Function(List<String>) configure,
    void Function() holdTheMintLock,
  }) client(
      {bool lockAlreadyHeld = false,
      List<String>? keyEstablishmentAlgorithms}) {
    var lockHeld = lockAlreadyHeld;
    final atClient = MockAtClient();
    // Swappable within one fixture, because two fixtures cannot stand in for
    // two builds of the same atSign: each has its own APKAM keypair, so the
    // second serves its own `_apsk` and the first's signed advertisement fails
    // verification. Same atSign, same key, different configuration is what a
    // rollout actually looks like.
    var preference = keyEstablishmentAlgorithms == null
        ? null
        : AtClientPreference(
            keyEstablishmentAlgorithms: keyEstablishmentAlgorithms);
    when(() => atClient.getPreferences()).thenAnswer((_) => preference);
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookUp();
    final trace = <String>[];
    final published = <String>[];
    // The atServer's copy of `public:__nskey.<ns>@alice`, by namespace.
    final advertised = <String, String>{};
    final chops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));

    when(() => atClient.atChops).thenReturn(chops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => lookUp.enrollmentId).thenReturn('enroll-a');
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      // Anything else is the `_apsk` an advertisement's signature is checked
      // against; one key serves every enrollment of this atSign here, since
      // authenticity is pinned in published_nskey_key_ring_test.
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
      if (builder is UpdateVerbBuilder) {
        final key = builder.atKey.key;
        if (key == '_nskeylock') {
          if (lockHeld) {
            // What the atServer says to the loser of the race.
            throw AtLookUpException(
                'AT0023', 'Immutable records may not be updated');
          }
        } else if (key.startsWith('__nskey')) {
          trace.add('publish:${builder.atKey.namespace}');
          published.add(builder.value as String);
          advertised[builder.atKey.namespace!] = builder.value as String;
        }
      }
      return 'data:1';
    });
    return (
      client: atClient,
      trace: trace,
      published: published,
      advertised: advertised,
      configure: (List<String> algorithms) => preference =
          AtClientPreference(keyEstablishmentAlgorithms: algorithms),
      holdTheMintLock: () => lockHeld = true,
    );
  }

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: atSign);
  }

  /// A sharing substrate that records what it was asked to push and to whom.
  ({MockSharing sharing, List<(Secret, Set<String>)> pushes}) sharing() {
    final mock = MockSharing();
    final pushes = <(Secret, Set<String>)>[];
    // A real store, because conveyance now writes the minted private into it
    // before pushing: the minter has to be able to ANSWER a later pull for
    // what it just minted, and the answering path reads this store. Left as a
    // bare mock, the getter returns null through noSuchMethod into a
    // non-nullable type and the push below never happens — with `dart analyze`
    // perfectly clean.
    when(() => mock.secretStore).thenReturn(SecretStore());
    when(() => mock.pushSecretToNamespaceMembers(any(),
            excludeEnrollmentIds: any(named: 'excludeEnrollmentIds')))
        .thenAnswer((inv) async {
      pushes.add((
        inv.positionalArguments[0] as Secret,
        inv.namedArguments[#excludeEnrollmentIds] as Set<String>,
      ));
      return 2;
    });
    return (sharing: mock, pushes: pushes);
  }

  /// Puts a generation on the fixture's atServer — a real keypair, signed, so
  /// it survives the same verify a peer's advertisement gets — and returns it.
  ///
  /// This stands for another of @alice's enrollments having published. Seeding
  /// the ring's own memory instead would be the wrong precondition: the whole
  /// point of the mint path's read is that it does not trust this client's
  /// caches to know what a sibling has done.
  Future<NskeyAdvertisement> publishedByAnother(
      MockAtClient client, Map<String, String> advertised) async {
    final pair = await XWingKeyPair.generate();
    final advertisement = NskeyAdvertisement.single(
      publicKey: pair.publicKeyBytes,
      alg: SecretSharingAlgos.xWing,
      suites: SecretSharingAlgos.openableSuitesFor(SecretSharingAlgos.xWing),
    );
    advertised[namespace] = await AtClientEnvelopeSigner(client)
        .wrapAndSignAndJsonEncode(advertisement.toPayload(),
            type: EnvelopeType.nskeyRing);
    return advertisement;
  }

  group('the rotation lever', () {
    test('the published advertisement carries a payload version', () async {
      // The reader accepts a payload with no `v` as the pre-2026-08-06 shape,
      // so nothing would notice the writer dropping it — which is precisely
      // why the writer needs its own assertion rather than a round trip.
      final c = client();
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());

      await ring.mintAndPublish(namespace);

      expect(c.published, hasLength(1));
      final envelope = jsonDecode(c.published.single) as Map<String, dynamic>;
      expect((SignedEnvelope.fromJson(envelope).payload as Map)['v'],
          nskeyAdvertisementVersion);
    });

    test('publishes a fresh generation and keeps the superseded private',
        () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

      // A first generation this client actually holds the private for, so the
      // retention claim is about a key it could otherwise have dropped.
      final first = await ring.mintAndPublish(namespace);
      final second = (await ring.rotate(namespace)).rotated;

      expect(second.nskeyKid, isNot(first.nskeyKid));
      expect(await filer.read(namespace, second.nskeyKid), isNotNull);
      expect(await filer.read(namespace, first.nskeyKid), isNotNull,
          reason: 'retained __ck records sealed to the superseded generation '
              'still have to open — rotation replaces the key, it does not '
              'decrypt or re-encrypt the past');
      expect(
          await ring.currentPublic(atSign, namespace),
          isA<NskeyAdvertisement>()
              .having((a) => a.nskeyKid, 'nskeyKid', second.nskeyKid),
          reason: 'and new writes must seal to the successor');

      // Fresh MATERIAL, not merely a fresh id. Differing kids already follow
      // from differing keys, because a kid is derived from the key it names —
      // so the kid assertion above says something about that derivation
      // rather than about what an enrollment cut out of the rotation ends up
      // holding. This compares the advertised keys themselves.
      expect(
          second.keys
              .map((k) => k.pub)
              .toSet()
              .intersection(first.keys.map((k) => k.pub).toSet()),
          isEmpty,
          reason: 'a rotation mints and carries nothing forward. That is what '
              'makes the previous generation worth nothing to an enrollment '
              'excluded from the push: no key in the successor is one it has '
              'ever held, so there is nothing to suppress and no special '
              'revocation path to write');
      expect(first.keys, isNotEmpty,
          reason: 'the positive control for the intersection above — two '
              'empty key lists intersect emptily, and would read as a clean '
              'rotation');
    });

    test('a rotation that loses the mint lock fails instead of adopting',
        () async {
      final c = client(lockAlreadyHeld: true);
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());
      final current = await publishedByAnother(c.client, c.advertised);

      await expectLater(ring.rotate(namespace), throwsA(isA<StateError>()),
          reason: 'a cold-start mint that loses the race adopts the winner and '
              'is done; a rotation that adopts what it finds has rotated '
              'nothing while reporting success, leaving the enrollment it was '
              'excluding holding the live generation');
      // The contrast that makes the point: the same loss on the mint path is a
      // resolution, not a failure.
      expect((await ring.mintAndPublish(namespace)).nskeyKid, current.nskeyKid);
      expect(c.trace, isEmpty, reason: 'and the loser publishes nothing');
    });

    test('rotating a namespace with no published key is refused', () async {
      final c = client();
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());

      await expectLater(ring.rotate(namespace), throwsA(isA<StateError>()),
          reason: 'that is a cold-start mint wearing a rotation\'s name, and a '
              'caller that meant to supersede a generation should hear there '
              'was none');
      expect(c.trace, isEmpty);
    });
  });

  group('rotation-time conveyance', () {
    test('seeding puts the minted private in the store it answers pulls from',
        () async {
      // The minter has to be able to SERVE what it just minted. The answering
      // path reads the secret store, and the store is filled from the keyfile
      // only by hydrateStoreFromFiling — which runs at bootstrap, before the
      // mint. Without the store write, the one enrollment guaranteed to hold
      // the generation offered an empty candidate list to every pull for it
      // and answered nothing until the process restarted, writing no envelope
      // and logging nothing.
      final c = client();
      // The legacy-PKAM shape, as the sibling test below uses: no enrollment,
      // namespaces named by the preference — the path seed() takes without a
      // roster round trip.
      final lookUp = c.client.getRemoteSecondary()!.atLookUp;
      when(() => lookUp.enrollmentId).thenReturn(null);
      when(() => c.client.getPreferences())
          .thenReturn(AtClientPreference()..namespace = namespace);
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      final s = sharing();
      // seed()'s push omits excludeEnrollmentIds, so stub that call shape.
      when(() => s.sharing.pushSecretToNamespaceMembers(any()))
          .thenAnswer((_) async => 1);

      expect(s.sharing.secretStore.listSecrets(), isEmpty,
          reason: 'the premise: nothing is in the store before the mint');

      final minted = await NskeySeeding(
              atClient: c.client,
              ring: ring,
              privateFiling: filer,
              sharing: s.sharing)
          .seed();
      expect(minted, {namespace});

      final kid = (await ring.currentPublic(atSign, namespace))!.nskeyKid;
      final held = s.sharing.secretStore
          .getSecret(namespace, '${NskeyPrivateFiling.secretNamePrefix}$kid');
      expect(held, isNotNull,
          reason: 'a pull for the generation this client just minted is '
              'answered from the secret store, so the mint has to leave it '
              'there');
      expect(base64Decode(held!.value),
          (await filer.readSeed(namespace, kid))!.bytes,
          reason: 'and it must be the SEED, which is what a receiver '
              're-derives the published public half from');
    });

    test('rotation puts the successor in the store it answers pulls from',
        () async {
      // The sibling of the mint-time case above, on the other path into
      // _mint. The rotating enrollment is the one certain to hold the
      // successor and, without this, the only one that cannot serve it — the
      // answering path reads the secret store, and hydrateStoreFromFiling has
      // already run by the time anything rotates.
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();

      final before = s.sharing.secretStore.listSecrets().length;

      final outcome = await NskeyRotation(
              atClient: c.client,
              ring: ring,
              privateFiling: filer,
              sharing: s.sharing)
          .rotateNamespaceKey(namespace);

      final held = s.sharing.secretStore.getSecret(namespace,
          '${NskeyPrivateFiling.secretNamePrefix}${outcome.advertisement.nskeyKid}');
      expect(held, isNotNull,
          reason: 'a pull for the generation this client just rotated to is '
              'answered from the secret store, so the rotation has to leave '
              'it there');
      expect(
          base64Decode(held!.value),
          (await filer.readSeed(namespace, outcome.advertisement.nskeyKid))!
              .bytes,
          reason: 'and it must be the SEED, which is what a receiver '
              're-derives the published public half from');
      expect(s.sharing.secretStore.listSecrets().length, before + 1,
          reason: 'the successor, and nothing else — the superseded '
              'generation is retained in the keyfile, not re-primed here');
    });

    test('pushes the successor private to the namespace members', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcome = await rotation.rotateNamespaceKey(namespace);

      expect(s.pushes, hasLength(1));
      final (secret, excluded) = s.pushes.single;
      expect(secret.namespace, namespace);
      expect(secret.name,
          '${NskeyPrivateFiling.secretNamePrefix}${outcome.advertisement.nskeyKid}');
      expect(
          base64Decode(secret.value),
          (await filer.readSeed(namespace, outcome.advertisement.nskeyKid))!
              .bytes,
          reason: 'what the other enrollments receive must be the durable '
              'SEED — not a value held only in the mint call, and not the '
              'expanded decapsulation key');
      expect(excluded, isEmpty);
      expect(outcome.conveyedTo, 2);
      expect(outcome.supersededKid, isNot(outcome.advertisement.nskeyKid));
    });

    // The mint-time push (NskeySeeding.seed -> _convey) shares the
    // conveyance discipline this file pins for rotation, and this rig is
    // the one that can actually mint — which is why the arm lives here.
    test('the mint-time push conveys the SEED too, under ML-KEM', () async {
      final c = client();
      // The legacy-PKAM shape: no enrollment, namespaces named by the
      // preference — the path seed() takes without a roster round trip.
      final lookUp = c.client.getRemoteSecondary()!.atLookUp;
      when(() => lookUp.enrollmentId).thenReturn(null);
      when(() => c.client.getPreferences()).thenReturn(AtClientPreference(
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024])
        ..namespace = namespace);
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      final s = sharing();
      // seed()'s push omits excludeEnrollmentIds, so stub that call shape.
      when(() => s.sharing.pushSecretToNamespaceMembers(any()))
          .thenAnswer((inv) async {
        s.pushes.add((inv.positionalArguments[0] as Secret, const {}));
        return 1;
      });

      final seeding = NskeySeeding(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);
      expect(await seeding.seed(), {namespace});

      final conveyed =
          Uint8List.fromList(base64Decode(s.pushes.single.$1.value));
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
      final rederived = await kem.keyPairFromSeed(conveyed);
      final advertised = await ring.currentPublic(atSign, namespace);
      expect(rederived.publicKey, advertised!.publicKey,
          reason: 'the receiver validates an arrival by re-deriving the '
              'advertised public half from it, which only the SEED can do');
    });

    test(
        'conveys a seed the receiver can re-derive the public half from, '
        'under ML-KEM where seed and decapsulation key differ', () async {
      final c = client();
      when(() => c.client.getPreferences()).thenReturn(AtClientPreference(
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]));
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcome = await rotation.rotateNamespaceKey(namespace);

      final conveyed =
          Uint8List.fromList(base64Decode(s.pushes.single.$1.value));
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
      final rederived = await kem.keyPairFromSeed(conveyed);
      expect(rederived.publicKey, outcome.advertisement.publicKey,
          reason: 'the receiver validates an arrival by re-deriving the '
              'advertised public half from it, which only the SEED can do — '
              'a conveyed decapsulation key is refused on arrival and the '
              'other enrollments never get the generation. X-Wing hid this: '
              'its seed and secretKey are the same bytes');
    });

    test('does not push to an excluded enrollment', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcome = await rotation
          .rotateNamespaceKey(namespace, excludeEnrollmentIds: {'enroll-b'});

      expect(s.pushes.single.$2, {'enroll-b'},
          reason: 'the exclusion has to reach the roster query, not merely be '
              'remembered by the caller');
      expect(outcome.excluded, {'enroll-b'});
    });

    test('a successor that cannot be read back is not conveyed', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      // A rotation whose ring files the private, paired with a filing that
      // cannot read it back: what the substrate would carry is unknown, so it
      // must carry nothing.
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling:
              NskeyPrivateFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign),
          sharing: s.sharing);

      await expectLater(
          rotation.rotateNamespaceKey(namespace), throwsA(isA<StateError>()));
      expect(s.pushes, isEmpty);
    });
  });

  test('a client with no key storage is refused a rotation', () async {
    final c = client();
    when(() => c.client.atKeysIo).thenReturn(null);

    expect(() => NskeyRotation.forClient(c.client), throwsA(isA<StateError>()),
        reason: 'the successor private would live only in memory and die with '
            'the process, leaving every peer sealing to a generation this '
            'atSign can no longer open — strictly worse than not rotating');
  });

  group('a generation holds a key per configured algorithm', () {
    test('a mint writes one key for each, and files each private', () async {
      // ⚠️ The mint wrote ONE key until 2026-08-28, under
      // keyEstablishmentAlgorithms.first — so an atSign configured for two
      // advertised one, and a peer that could only use the other was refused.
      final c = client(keyEstablishmentAlgorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024,
      ]);
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

      final minted = await ring.mintAndPublish(namespace);

      expect(minted.keys.map((k) => k.alg).toList(),
          [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024],
          reason: 'in the preference\'s own order, which is the order a sender '
              'with no narrowing takes them in');
      for (final key in minted.keys) {
        expect(await filer.read(namespace, key.kid), isNotNull,
            reason: '${key.alg} is advertised, so its private must be filed '
                'under its own kid — an entry peers seal to and nobody can '
                'open is worse than one that was never advertised');
      }
      expect(minted.suites.length, greaterThan(1),
          reason: 'what the generation can open is derived from the keys it '
              'holds, so a second key widens it');
    });

    test('a rotation mints the whole configured set afresh', () async {
      final c = client(keyEstablishmentAlgorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024,
      ]);
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      final first = await ring.mintAndPublish(namespace);

      final second = (await ring.rotate(namespace)).rotated;

      expect(second.keys.map((k) => k.alg).toList(),
          first.keys.map((k) => k.alg).toList());
      expect(
          second.keys
              .map((k) => k.pub)
              .toSet()
              .intersection(first.keys.map((k) => k.pub).toSet()),
          isEmpty,
          reason: 'fresh-only applies per key, not per generation: a rotation '
              'that carried one algorithm forward would hand an excluded '
              'enrollment a key it already held');
      expect(first.keys, isNotEmpty, reason: 'the positive control');
    });

    test('an unmintable set never reaches the mint — the preference refuses it',
        () {
      // Where the guard lives, asserted so the ring's absence of one is a
      // decision rather than an oversight. A ring that re-checked would be
      // making a claim about this class rather than a check of its own, and
      // the branch would be unreachable.
      expect(
          () => AtClientPreference(
              keyEstablishmentAlgorithms: const ['kem-from-the-future']),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('this build mints'))));
      expect(
          () => AtClientPreference(keyEstablishmentAlgorithms: const []),
          throwsA(isA<ArgumentError>().having((e) => '$e', 'message',
              contains('can receive nothing sealed to it'))));
    });
  });

  group('the add lever', () {
    List<String> both() => const [
          SecretSharingAlgos.xWing,
          SecretSharingAlgos.mlKem1024,
        ];

    test('joins the current generation in place, keeping its identity',
        () async {
      // The rollout-1 case: a generation minted by a build configured for one
      // algorithm, and the same install upgraded to a build configured for two
      // finding its own missing.
      final c =
          client(keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing]);
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      final before = await ring.mintAndPublish(namespace);
      expect(before.keys, hasLength(1));

      c.configure(both());
      final widened = await ring.add(namespace);

      expect(widened, isNotNull);
      expect(widened!.keys.map((k) => k.alg).toList(),
          [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);
      expect(widened.keys.first.kid, before.keys.single.kid,
          reason: 'the existing entry keeps its id, or every peer holding a '
              'content key sealed to it re-cuts for nothing');
      expect(widened.keys.first.pub, before.keys.single.pub);
      expect(widened.createdAt, before.createdAt,
          reason: 'and the generation keeps its own createdAt. Refreshing it '
              'would make a generation minted before a revocation read as one '
              'minted after, and the rotation that revocation is owed would '
              'never fire');
      expect(await filer.read(namespace, widened.keys.last.kid), isNotNull,
          reason: 'the added private is filed under its own kid');
    });

    test('adds nothing when the generation already carries the set', () async {
      final c = client(keyEstablishmentAlgorithms: both());
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      final minted = await ring.mintAndPublish(namespace);
      final publishes = c.trace.where((t) => t.startsWith('publish')).length;

      final again = await ring.add(namespace);

      expect(again!.keys.map((k) => k.kid).toList(),
          minted.keys.map((k) => k.kid).toList());
      expect(c.trace.where((t) => t.startsWith('publish')).length, publishes,
          reason: 'a no-op add must not rewrite the record: every rewrite is a '
              'chance for a concurrent rotation to be rolled back');
    });

    test('a namespace with nothing published is a mint, not an add', () async {
      final c = client(keyEstablishmentAlgorithms: both());
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());

      expect(await ring.add(namespace), isNull);
      expect(c.trace.where((t) => t.startsWith('publish')), isEmpty,
          reason: 'mintAndPublish resolves a lost election by ADOPTING, which '
              'an add must never do — it would report success having added '
              'nothing');
    });

    test('a client that loses the mint lock adds nothing', () async {
      final c =
          client(keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing]);
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();

      // Another enrollment takes the lock between this client deciding to add
      // and getting there — the race the lock exists for.
      c.holdTheMintLock();
      c.configure(both());

      expect(await ring.add(namespace), isNull,
          reason: 'two clients adding at once is a read-mutate-write over one '
              'record, and the loser would overwrite the winner\'s entry');
      expect(c.trace.where((t) => t.startsWith('publish')), isEmpty);
    });
  });

  group('the revocation composition', () {
    ({MockEnrollmentService service, List<String> order}) enrollmentService(
        MockAtClient atClient,
        {Map<String, dynamic>? grants,
        List<String>? order,
        Map<String, dynamic> callerGrants = const {
          '*': 'rw',
          '__manage': 'rw'
        }}) {
      final service = MockEnrollmentService();
      final trace = order ?? <String>[];
      when(() => atClient.enrollmentService).thenReturn(service);
      when(() => service.fetchEnrollmentRequests(
              enrollmentListParams: any(named: 'enrollmentListParams')))
          .thenAnswer((_) async => [
                // The caller's own record. The atServer always returns it, and
                // it is what says whether this client may revoke at all.
                Enrollment()
                  ..enrollmentId = 'enroll-a'
                  ..namespace = callerGrants,
                Enrollment()
                  ..enrollmentId = 'enroll-b'
                  ..namespace = grants ?? {namespace: 'rw'}
              ]);
      when(() => service.revoke(any())).thenAnswer((inv) async {
        trace.add(
            'revoke:${(inv.positionalArguments[0] as EnrollmentRequestDecision).enrollmentId}');
        return AtEnrollmentResponse('enroll-b', EnrollmentStatus.revoked);
      });
      return (service: service, order: trace);
    }

    test('revokes before it rotates', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final e = enrollmentService(c.client, order: c.trace);
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: sharing().sharing);

      await rotation.revokeEnrollmentAndRotate('enroll-b');

      expect(c.trace, ['revoke:enroll-b', 'publish:$namespace'],
          reason: 'the ordering IS the enforcement: revoking first drops the '
              'enrollment out of enroll:listns, so by the time the rotation '
              'runs it is refused at every serve — rotate first and it can '
              'simply pull the successor from another holder in the gap');
      expect(e.service, isNotNull);
    });

    test('rotates every granted namespace, excluding the revoked id', () async {
      const other = 'app_2.my_apps';
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      await ring.mintAndPublish(other);
      final s = sharing();
      enrollmentService(c.client,
          grants: {namespace: 'rw', other: 'r', '__manage': 'rw', '*': 'rw'});
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      final outcomes = await rotation.revokeEnrollmentAndRotate('enroll-b');

      expect(outcomes.map((o) => o.namespace).toSet(), {namespace, other},
          reason: 'a read grant still hands over every key the namespace '
              'protects, so "could read it" is the bar, not "could write it"');
      expect(s.pushes.map((p) => p.$2), everyElement({'enroll-b'}));
      expect(outcomes.map((o) => o.namespace), isNot(contains('__manage')),
          reason: 'enrollment administration is not an app namespace');
      expect(outcomes.map((o) => o.namespace), isNot(contains('*')),
          reason: 'a wildcard authorises every namespace and is not itself '
              'one — there is no public:__nskey.* to overwrite');
    });

    test('one namespace failing to rotate does not abandon the rest', () async {
      const unminted = 'app_3.my_apps';
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      final s = sharing();
      enrollmentService(c.client, grants: {unminted: 'rw', namespace: 'rw'});
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      logs.records.clear();
      final outcomes = await rotation.revokeEnrollmentAndRotate('enroll-b');

      expect(outcomes.map((o) => o.namespace), [namespace],
          reason: 'the revoke has already landed, so abandoning the remainder '
              'would leave the atSign with an enrollment cut off from the '
              'server but still holding every live namespace key it had');

      // The control, and it is deliberately NOT drawn from the property under
      // test: this line is emitted by the same call whatever the rotations
      // do. It stays green when the severe record below is downgraded — the
      // failure that assertion exists to catch — and goes red when the
      // handler never bound, which is the failure that would otherwise let an
      // empty recorder satisfy every level assertion by matching nothing.
      // First, so an unbound recorder is reported as an unbound recorder
      // rather than as a missing SEVERE record.
      expect(
          logs
              .at('INFO')
              .where((m) => m.startsWith('Revoked enrollment enroll-b')),
          hasLength(1),
          reason: 'if this is empty the recorder is not bound and the SEVERE '
              'assertion below measured nothing');

      // The LEVEL is the contract here, not decoration. A namespace that
      // failed to rotate is simply absent from `outcomes` — indistinguishable
      // from one that needed nothing — so this record is the only thing that
      // tells an operator an enrollment they just revoked still holds a live
      // generation and can open data written under it. Logged at `finer` it
      // would not reach a default deployment's log at all, and the omission
      // would read as success.
      expect(logs.at('SEVERE').where((m) => m.contains(unminted)), hasLength(1),
          reason: 'the namespace this call could not rotate has to be named, '
              'at a level an operator sees, or the caller is told nothing at '
              'all about the one thing it must now do by hand');
    });

    test('an unknown enrollment revokes nothing and rotates nothing', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final s = sharing();
      enrollmentService(c.client, order: c.trace);
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      await expectLater(rotation.revokeEnrollmentAndRotate('enroll-ghost'),
          throwsA(isA<StateError>()));
      expect(c.trace, isEmpty);
      expect(s.pushes, isEmpty);
    });

    test('a caller without __manage is refused, and revokes nothing', () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final s = sharing();
      enrollmentService(c.client,
          order: c.trace, callerGrants: {namespace: 'rw'});
      final rotation = NskeyRotation(
          atClient: c.client,
          ring: ring,
          privateFiling: filer,
          sharing: s.sharing);

      await expectLater(rotation.revokeEnrollmentAndRotate('enroll-b'),
          throwsA(isA<StateError>()));
      expect(c.trace, isEmpty);
      expect(s.pushes, isEmpty,
          reason: 'the two halves ask for different privileges and only one is '
              'obvious: rotating needs rw on the namespace, revoking needs '
              '__manage. Without it the atServer also returns only this '
              'client\'s OWN enrollment record, so the failure would surface '
              'as "no enrollment <id> to revoke" and send the caller looking '
              'for a wrong id');
    });
  });
}
