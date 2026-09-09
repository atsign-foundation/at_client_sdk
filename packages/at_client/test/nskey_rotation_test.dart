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

/// The nskey-keypair rotation lever and the revocation it composes with.
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
  /// it was asked to do and serving back whatever has been published.
  ///
  /// [lockAlreadyHeld] makes the mint lock's immutable create fail, which is
  /// how the atServer reports that another enrollment holds it;
  /// `holdTheMintLock` and `releaseTheMintLock` move that same switch after
  /// construction.
  ({
    MockAtClient client,
    List<String> trace,
    List<String> published,
    Map<String, String> advertised,
    void Function(List<String>) configure,
    void Function() holdTheMintLock,
    void Function() releaseTheMintLock,
  }) client(
      {bool lockAlreadyHeld = false,
      List<String>? keyEstablishmentAlgorithms}) {
    var lockHeld = lockAlreadyHeld;
    final atClient = MockAtClient();
    // NOTE: a second fixture cannot stand in for a second build of the same
    // atSign — it has its own APKAM keypair, so it serves its own `_apsk` and
    // the first's signed advertisement fails verification. That is why this is
    // swappable in place.
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
      // Anything but `__nskey` is the `_apsk` an advertisement's signature is
      // checked against.
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
      releaseTheMintLock: () => lockHeld = false,
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
    // NOTE: a real store, not a bare mock — the getter would return null
    // through noSuchMethod into a non-nullable type and the push below would
    // never happen, with `dart analyze` clean.
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
  /// it survives the same verify a peer's advertisement gets — standing for
  /// another of this atSign's enrollments having published, and returns it.
  ///
  /// [createdAt] back-dates the generation, which is what an age-shaped
  /// rotation policy decides on; it defaults to now.
  Future<NskeyAdvertisement> publishedByAnother(
      MockAtClient client, Map<String, String> advertised,
      {DateTime? createdAt}) async {
    final pair = await XWingKeyPair.generate();
    final advertisement = NskeyAdvertisement.single(
      publicKey: pair.publicKeyBytes,
      alg: SecretSharingAlgos.xWing,
      createdAt: createdAt,
      suites: SecretSharingAlgos.openableSuitesFor(SecretSharingAlgos.xWing),
    );
    advertised[namespace] = await AtClientEnvelopeSigner(client)
        .wrapAndSignAndJsonEncode(advertisement.toPayload(),
            type: EnvelopeType.nskeyRing);
    return advertisement;
  }

  group('the rotation lever', () {
    test('the published advertisement carries a payload version', () async {
      // The reader accepts a payload with no `v`, so nothing would notice the
      // writer dropping it — hence an assertion on the writer rather than a
      // round trip.
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

    test('retirement here is GENERATIONAL, never an entry marked retired',
        () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

      final first = await ring.mintAndPublish(namespace);
      final second = (await ring.rotate(namespace)).rotated;

      expect(second.keys, isNotEmpty, reason: 'the positive control');
      for (final entry in second.keys) {
        expect(KeyEntryStatus.offersNewOperations(entry.status), isTrue,
            reason: 'every entry of the successor generation is offered for '
                'new work. A retired one here would mean this substrate had '
                'adopted the signing side\'s mechanism — and the point of the '
                'clause is that the two reach the same guarantee by different '
                'ones');
      }

      expect(await filer.read(namespace, first.nskeyKid), isNotNull,
          reason: 'the superseded private is what opens a retained __ck sealed '
              'to it; on this substrate that is the whole of retirement');
      expect(first.nskeyKid, isNot(second.nskeyKid),
          reason: 'the control for the line above: two generations, or "the '
              'previous private is held" is a claim about the current one');
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

  // NOTE: nothing on this path is timer-driven — it neither sleeps, backs off
  // nor reads the lock's ttl. The question is re-put by the next client start
  // and by the next content key conveyed to a namespace this atSign owns, so a
  // re-ask can land while the lock is still held and be refused again. What
  // these arms pin is the re-read and the re-decide, not any interval between
  // them.
  group('the lock loser re-decides rather than queueing', () {
    test('a lock loser publishes nothing and still rotates at the next ask',
        () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      await ring.mintAndPublish(namespace);
      c.trace.clear();
      final s = sharing();
      final asks = <NskeyRotationContext>[];
      final seeding = NskeySeeding(
        atClient: c.client,
        ring: ring,
        privateFiling: filer,
        sharing: s.sharing,
        rotationPolicy: (ns) {
          asks.add(ns);
          return true;
        },
      );

      c.holdTheMintLock();

      expect(await seeding.rotateIfPolicyAsks(atSign, namespace), isFalse,
          reason: 'and it returns while the lock is still held — nothing '
              'releases it until this test does, so a client that queued '
              'behind the holder would never reach the rest of this test');
      expect(asks, hasLength(1),
          reason: 'the control: the policy WAS asked, and this one always says '
              'yes — so the false above is the rotation being refused rather '
              'than an application declining one');
      expect(c.trace, isEmpty, reason: 'and the loser publishes nothing');

      c.releaseTheMintLock();

      expect(await seeding.rotateIfPolicyAsks(atSign, namespace), isTrue);
      expect(asks, hasLength(2),
          reason: 'the question is put AGAIN rather than answered from the '
              'first refusal, which is what makes the second pass a decision '
              'instead of a replay of one already made');
      expect(asks.last.nskeyKid, asks.first.nskeyKid,
          reason: 'nobody rotated in the meantime, so the re-read finds the '
              'same generation and the answer is still yes — the half of '
              'converging where this client is the one that must act');
      expect(asks.last.createdAt, asks.first.createdAt);
      expect(c.trace, ['publish:$namespace'],
          reason: 'the only publish since the setup mint, and it comes from '
              'the pass that took the lock');
    });

    test('a lock loser that re-reads a fresher generation decides against it',
        () async {
      final c = client();
      final filer = await filing();
      final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);
      final stale = await publishedByAnother(c.client, c.advertised,
          createdAt: DateTime.now().toUtc().subtract(const Duration(days: 30)));
      final s = sharing();
      final asks = <NskeyRotationContext>[];
      // One age-shaped closure, so the difference between the two answers is
      // the input and not the policy.
      final seeding = NskeySeeding(
        atClient: c.client,
        ring: ring,
        privateFiling: filer,
        sharing: s.sharing,
        rotationPolicy: (ns) {
          asks.add(ns);
          return ns.age >= const Duration(days: 7);
        },
      );

      c.holdTheMintLock();

      expect(await seeding.rotateIfPolicyAsks(atSign, namespace), isFalse);
      expect(asks.single.nskeyKid, stale.nskeyKid);
      expect(asks.single.age, greaterThanOrEqualTo(const Duration(days: 7)),
          reason: 'the control: this policy answered YES on the first pass, so '
              'the false above is the lock. A policy that had said no would '
              'satisfy every assertion below with no contention anywhere');
      expect(c.trace, isEmpty);

      final fresh = await publishedByAnother(c.client, c.advertised);
      c.releaseTheMintLock();

      expect(await seeding.rotateIfPolicyAsks(atSign, namespace), isFalse,
          reason: 'the work the policy asked for has happened, so the second '
              'pass asks for nothing — the half of converging where another '
              'client did what was needed');
      expect(asks, hasLength(2));
      expect(asks.last.nskeyKid, fresh.nskeyKid,
          reason: 'the second ask is decided on a RE-READ of the atServer, so '
              'it carries the winner\'s generation rather than the one this '
              'client was holding when it lost');
      expect(asks.last.createdAt.isAfter(asks.first.createdAt), isTrue,
          reason: 'and it carries the winner\'s createdAt, which is what an '
              'age-shaped policy answers no to');
      expect(asks.last.age, lessThan(const Duration(days: 7)));
      expect(c.trace, isEmpty,
          reason: 'nothing was published on either pass: the lock loser adds '
              'no second generation, which is the whole of converging rather '
              'than storming');
      expect(s.pushes, isEmpty,
          reason: 'and nothing was conveyed, so no enrollment was handed a '
              'private for a generation this atSign does not advertise');
    });
  });

  group('rotation-time conveyance', () {
    test('seeding puts the minted private in the store it answers pulls from',
        () async {
      final c = client();
      // The legacy-PKAM shape: no enrollment, namespaces named by the
      // preference — the path seed() takes without a roster round trip.
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

    test('a rotation drops an algorithm this client no longer mints', () async {
      // NOTE: the drop is decided by THIS client's configuration alone. A
      // sibling still configured for ml-kem-1024 puts it straight back through
      // the add lever, which its startup seeding reaches for any namespace
      // already published — so this asserts the removal, not that the fleet
      // has finished with the algorithm.
      final c = client(keyEstablishmentAlgorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024,
      ]);
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());
      await ring.mintAndPublish(namespace);

      c.configure(const [SecretSharingAlgos.xWing]);
      final rotation = await ring.rotate(namespace);

      expect(rotation.superseded.keys.map((k) => k.alg),
          contains(SecretSharingAlgos.mlKem1024),
          reason: 'the control, and it can go red while the assertion below '
              'stays green: a ring that never minted ml-kem-1024 at all would '
              'satisfy every absence here with nothing having been dropped');
      expect(rotation.rotated.keys.map((k) => k.alg).toList(),
          [SecretSharingAlgos.xWing],
          reason: 'the successor holds what this client\'s configured set '
              'minted and nothing else, so narrowing that set is the whole of '
              'what takes an algorithm out of the advertisement');
      expect(rotation.rotated.suites,
          isNot(contains(SecretSharingAlgos.mlKem1024Rfc9180)),
          reason: 'and what the atSign says it can open narrows with the keys '
              'it holds, since suites is derived from them — a successor still '
              'naming the dropped construction would offer to open something '
              'no key in the generation can');
    });

    test('an algorithm a rotation dropped is not added back', () async {
      final c = client(keyEstablishmentAlgorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024,
      ]);
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());
      final first = await ring.mintAndPublish(namespace);
      expect(
          first.keys.map((k) => k.alg), contains(SecretSharingAlgos.mlKem1024),
          reason: 'the control: with ml-kem-1024 never minted the rotation '
              'drops nothing and there is nothing for the add to put back');

      c.configure(const [SecretSharingAlgos.xWing]);
      final rotated = (await ring.rotate(namespace)).rotated;
      final publishes = c.trace.where((t) => t.startsWith('publish')).length;

      final again = await ring.add(namespace);

      expect(again!.keys.map((k) => k.alg),
          isNot(contains(SecretSharingAlgos.mlKem1024)));
      expect(again.keys.map((k) => k.kid).toList(),
          rotated.keys.map((k) => k.kid).toList(),
          reason: 'the generation comes back unchanged — the same entries, and '
              'no entry for the algorithm the rotation dropped');
      expect(c.trace.where((t) => t.startsWith('publish')).length, publishes,
          reason: 'and the record is not rewritten: an add that found '
              'something missing would publish, and every rewrite is a chance '
              'for a concurrent rotation to be rolled back');
    });

    test('an unmintable set never reaches the mint — the preference refuses it',
        () {
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
      // A generation minted by a build configured for one algorithm, and the
      // same install upgraded to a build configured for two finding its own
      // missing.
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

      c.holdTheMintLock();
      c.configure(both());

      expect(await ring.add(namespace), isNull,
          reason: 'two clients adding at once is a read-mutate-write over one '
              'record, and the loser would overwrite the winner\'s entry');
      expect(c.trace.where((t) => t.startsWith('publish')), isEmpty);
    });
  });

  group('the revocation composition', () {
    /// An enrollment service holding the caller's own record and `enroll-b`,
    /// recording each revoke into the returned trace.
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
                // The caller's own record: the atServer always returns it, and
                // it says whether this client may revoke at all.
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

      expect(
          logs
              .at('INFO')
              .where((m) => m.startsWith('Revoked enrollment enroll-b')),
          hasLength(1),
          reason: 'if this is empty the recorder is not bound and the SEVERE '
              'assertion below measured nothing');

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
