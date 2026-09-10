import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientEnvelopeSigner;
import 'package:at_client/src/crypto/nskey/mint_lock.dart'
    show MintLease, MintLock;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

/// A bare mock, shadowing the shared one in `test_utils/mocks.dart` whose
/// concrete `getPreferences()` override cannot be stubbed.
class MockAtClient extends Mock implements AtClient {}

/// A lock that is taken successfully and hands out a lease that has already
/// run out — the slow-winner case, without waiting for a real ttl.
class _SpentLeaseLock extends MintLock {
  _SpentLeaseLock(super.atClient);

  @override
  Future<T?> withLock<T>(
          AtKey lockKey, Future<T> Function(MintLease lease) mint,
          {bool ownLockIsNotContention = false}) =>
      mint(MintLease(DateTime.now().subtract(const Duration(seconds: 1))));
}

/// Minting a namespace key: the interlock between an atSign's own
/// enrollments, and the ordering that stops a key being published before
/// anyone can open it.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  /// A client whose remote verbs succeed, recording what was sent, and serving
  /// back whatever has been published to the one record these tests turn on.
  /// [lockAlreadyHeld] makes the lock's immutable create fail, which is how the
  /// atServer reports that another enrollment already holds it.
  ({
    MockAtClient client,
    List<AtKey> verbs,
    List<Object> builders,
    Map<String, String?> values,
    Map<String, DateTime> verbTimes,
    Map<String, String> advertised,

    /// The `updatedAt` the atServer serves with the advertisement record, by
    /// namespace. Absent unless a test sets one.
    Map<String, DateTime> advertisedStamps,
    List<GetRequestOptions?> advertisementReads,

    /// [takeDelay] makes the lock's own take slow, which is the only way to
    /// tell a lease stamped BEFORE the request from one stamped after it.
  }) client(
      {bool lockAlreadyHeld = false, Duration takeDelay = Duration.zero}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookUp();
    final verbs = <AtKey>[];
    // NOTE: every builder, not only the updates — a recorder that kept only
    // updates cannot tell an absent delete from an unrecorded one.
    final builders = <Object>[];
    final values = <String, String?>{};
    final verbTimes = <String, DateTime>{};
    // The atServer's copy of `public:__nskey.<ns>@alice`, by namespace.
    final advertised = <String, String>{};
    final advertisedStamps = <String, DateTime>{};
    final advertisementReads = <GetRequestOptions?>[];
    final chops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));

    when(() => atClient.atChops).thenReturn(chops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => lookUp.enrollmentId).thenReturn('enroll-a');
    // NOTE: an EMPTY roster, and said rather than left unstubbed. A read miss
    // broadcasts a pull to the namespace's other enrollments, and here there
    // are none - which is the situation these tests are in. Matched on the
    // command so no other verb is answered by accident;
    // `listForNamespace` refuses to read an unparseable response as an empty
    // roster on purpose, because that would withhold key material from every
    // member of the namespace.
    when(() => secondary.executeCommand(any(that: startsWith('enroll:listns')),
        auth: any(named: 'auth'))).thenAnswer((_) async => 'data:[]');
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      // Anything that is not the advertisement is the `_apsk` its signature is
      // checked against — one key for every enrollment of this atSign, so an
      // advertisement signed by the fixture verifies whichever enrollment it
      // claims.
      if (key.key != '__nskey') {
        return AtValue()
          ..value = chops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;
      }
      advertisementReads
          .add(inv.namedArguments[#getRequestOptions] as GetRequestOptions?);
      final serving = advertised[key.namespace];
      if (serving == null) throw AtKeyNotFoundException('$key');
      final stamp = advertisedStamps[key.namespace];
      return AtValue()
        ..value = serving
        ..metadata = stamp == null ? null : (Metadata()..updatedAt = stamp);
    });

    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as Object;
      builders.add(builder);
      if (builder is UpdateVerbBuilder) {
        verbs.add(builder.atKey);
        verbTimes[builder.atKey.key] = DateTime.now();
        values[builder.atKey.key] = builder.value;
        if (builder.atKey.key == '_nskeylock' && takeDelay > Duration.zero) {
          await Future<void>.delayed(takeDelay);
        }
        if (builder.atKey.key == '_nskeylock' && lockAlreadyHeld) {
          // What the atServer says to the loser of the race.
          throw AtLookUpException(
              'AT0023', 'Immutable records may not be updated');
        }
        if (builder.atKey.key == '__nskey') {
          advertised[builder.atKey.namespace!] = builder.value as String;
        }
      }
      return 'data:1';
    });
    return (
      client: atClient,
      verbs: verbs,
      builders: builders,
      values: values,
      verbTimes: verbTimes,
      advertised: advertised,
      advertisedStamps: advertisedStamps,
      advertisementReads: advertisementReads,
    );
  }

  Future<NskeyPrivateFiling> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return NskeyPrivateFiling(keysIo: io, atSign: atSign);
  }

  test('the advertisement is written to the atServer and nowhere else',
      () async {
    final c = client();
    final filer = await filing();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

    final advertisement = await ring.mintAndPublish(namespace);

    expect(c.values['__nskey'], isNotNull);
    expect(c.advertised[namespace], c.values['__nskey']);
    expect(advertisement.nskeyKid, isNotEmpty);

    // NOTE: a local put would queue the key's name for a sync push that sends
    // whatever local storage holds when it drains, putting the superseded
    // generation back on the atServer.
    verifyNever(() => c.client
        .put(any(), any(), putRequestOptions: any(named: 'putRequestOptions')));
  });

  test('the private is durable before the public half is published', () async {
    final c = client();
    final filer = await filing();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: filer);

    final advertisement = await ring.mintAndPublish(namespace);

    expect(await filer.read(namespace, advertisement.nskeyKid), isNotNull,
        reason: 'a key published ahead of its private leaves every sender '
            'sealing to something nobody can open, and rotation replaces the '
            'key rather than decrypting what was written meanwhile');
    final published = c.verbs.where((k) => k.key.startsWith('__nskey') == true);
    expect(published, hasLength(1));
  });

  test('a ring built from the client alone files into the client\'s keyfile',
      () async {
    final c = client();
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    when(() => c.client.atKeysIo).thenReturn(io);

    final ring = PublishedNskeyKeyRing(c.client);
    expect(ring.privateFiling, isNotNull,
        reason: 'the mechanism: a ring given no filing derives one from the '
            'client. Without this the read below could pass on the ring\'s '
            'own in-memory copy and prove nothing about durability');

    final advertisement = await ring.mintAndPublish(namespace);

    // Read through a SEPARATE filing over the same key source, standing for
    // the next process: what is asserted is that the seed reached the keyfile,
    // not that the ring that minted it remembers it.
    expect(
        await NskeyPrivateFiling(keysIo: io, atSign: atSign)
            .read(namespace, advertisement.nskeyKid),
        isNotNull);
  });

  test('and a client with no key source mints into memory only', () async {
    // NOTE: `atKeysIo` is left unstubbed, so mocktail answers null and there is
    // nothing to derive a filing from.
    final c = client();

    final ring = PublishedNskeyKeyRing(c.client);
    expect(ring.privateFiling, isNull);

    final advertisement = await ring.mintAndPublish(namespace);
    expect(advertisement.nskeyKid, isNotEmpty);
    expect(c.verbs.where((k) => k.key.startsWith('__nskey') == true),
        hasLength(1));
  });

  test('the published advertisement emits its exact wire shape — raw literals',
      () async {
    // NOTE: raw strings deliberately — an assertion made through the constants
    // that define these values follows a change silently, so only this pin
    // fails when the wire moves. The entry spelling `{use, alg, pub, kid}`
    // inside `{v, createdAt, keys, suites}` is shared with the `_apsk`
    // advertisement and the enrollment key package, so a field renamed here is
    // a field renamed in three records.
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    final advertisement = await ring.mintAndPublish(namespace);

    final envelope = jsonDecode(c.values['__nskey']!) as Map<String, dynamic>;
    expect(envelope.keys.toList(), ['payload', 'signatures'],
        reason: 'the envelope — RFC 7515 general JSON serialization, pinned '
            'as shape documentation');
    final payload = (SignedEnvelope.fromJson(envelope).payload as Map)
        .cast<String, dynamic>();
    expect(payload.keys.toList(), ['v', 'createdAt', 'keys', 'suites'],
        reason: 'the payload — frozen forever');
    expect(payload['v'], 1);
    expect(payload['suites'], ['x-wing-rfc9180-v1']);

    final keys = (payload['keys'] as List).cast<Map<String, dynamic>>();
    expect(keys, hasLength(1),
        reason: 'a mint advertises one key; the list is what lets a second '
            'algorithm be added beside it later');
    expect(keys.single.keys.toList(), ['kid', 'use', 'alg', 'pub'],
        reason: 'the entry — the vocabulary all three advertising records use');
    expect(keys.single['use'], 'enc');
    expect(keys.single['alg'], 'x-wing');
    expect(keys.single['kid'], advertisement.nskeyKid);
  });

  group('the record stamp says when the generation was minted', () {
    // `updatedAt` on `public:__nskey.<ns>@alice` only means "when this
    // generation was minted" because an add puts the atServer's own previous
    // value back while a rotation lets it stamp afresh.
    const stamped = '2026-03-04T05:06:07.000008Z';
    final stamp = DateTime.parse(stamped);

    /// The `update` command each `__nskey` write emitted, in order.
    List<String> advertisementCommands(List<Object> builders) => builders
        .whereType<UpdateVerbBuilder>()
        .where((b) => b.atKey.key == '__nskey')
        .map((b) => b.buildCommand())
        .toList();

    test('an add asserts it back — raw literal', () async {
      final c = client();
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());
      await ring.mintAndPublish(namespace);
      // The atServer's stamp on what was just published.
      c.advertisedStamps[namespace] = stamp;
      when(() => c.client.getPreferences())
          .thenReturn(AtClientPreference(keyEstablishmentAlgorithms: const [
        SecretSharingAlgos.xWing,
        SecretSharingAlgos.mlKem1024,
      ]));

      final widened = await ring.add(namespace);

      expect(widened?.keys, hasLength(2),
          reason: 'the add really added, so the command below is an add\'s and '
              'not a second mint\'s');
      final commands = advertisementCommands(c.builders);
      expect(commands, hasLength(2));
      expect(commands.last, contains(':uAt:$stamped'),
          reason: 'the at-protocol fragment, raw: `:uAt:` is what the atServer '
              'parses, and it carries the value the record already had');
    });

    test('and a rotation does not — the control', () async {
      final c = client();
      final ring =
          PublishedNskeyKeyRing(c.client, privateFiling: await filing());
      await ring.mintAndPublish(namespace);
      c.advertisedStamps[namespace] = stamp;

      await ring.rotate(namespace);

      final commands = advertisementCommands(c.builders);
      expect(commands, hasLength(2));
      expect(commands.last, isNot(contains(':uAt:')),
          reason: 'a rotation takes a fresh server stamp, which is what makes '
              'the comparison mean anything. Same fixture, same served stamp, '
              'same record as the arm above — only the operation differs');
    });
  });

  test('a mint that cannot store its private publishes nothing', () async {
    final c = client();
    // Key storage with nothing in it for this atSign: `read` throws, so
    // `store` cannot persist.
    final ring = PublishedNskeyKeyRing(c.client,
        privateFiling:
            NskeyPrivateFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign));

    await expectLater(
        ring.mintAndPublish(namespace), throwsA(isA<StateError>()));
    expect(c.verbs.where((k) => k.key.startsWith('__nskey') == true), isEmpty,
        reason: 'the advertisement is the promise that a private exists; '
            'making it when one does not is the failure this ordering exists '
            'to prevent');
  });

  test('the lock is taken remotely, before anything is published', () async {
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    await ring.mintAndPublish(namespace);

    expect(c.verbs.first.key, '_nskeylock',
        reason: 'the atServer refusing a second immutable create is the only '
            'thing serialising two enrollments — a local-first put would let '
            'both believe they won and collide at sync');
    expect(c.verbs.first.metadata.immutable, isTrue);
    expect(c.verbs.first.metadata.ttl, isNotNull,
        reason: 'a holder that dies mid-mint must not block its atSign for '
            'good');
  });

  test('the winner does not release the lock — the ttl does', () async {
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    await ring.mintAndPublish(namespace);

    expect(c.builders.whereType<DeleteVerbBuilder>(), isEmpty,
        reason: 'the lock is an election token with a cooldown, not a mutex. '
            'Deleting it on the way out is how a holder finishing late removed '
            'its SUCCESSOR\'s lock — the delete forced past the immutable '
            'record without checking it still owned the one it removed');
    expect(c.verbs.where((k) => k.key == '_nskeylock'), hasLength(1));
    expect(c.verbs.first.metadata.ttl, isNotNull,
        reason: 'and with nothing deleting it, the ttl is the only thing that '
            'ever frees it — a lock without one would block minting for good');
  });

  test('a lock key with no ttl is refused outright', () async {
    final c = client();

    await expectLater(
        MintLock(c.client).withLock(
            AtKey()
              ..key = '_nskeylock'
              ..sharedBy = atSign
              ..metadata = (Metadata()..immutable = true),
            (_) async => 'minted'),
        throwsA(isA<ArgumentError>()),
        reason: 'nothing else releases it, so a lock without a ttl is not a '
            'lock held too long — it is one held for good');
    expect(c.verbs, isEmpty,
        reason: 'and it is refused before the take goes out, so the '
            'unreleasable record is never created in the first place');
  });

  test('a loser with nothing published fails rather than minting', () async {
    final c = client(lockAlreadyHeld: true);
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    await expectLater(
        ring.mintAndPublish(namespace),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('holds the mint lock'), contains('must not mint')))),
        reason: 'a put waiting on a namespace key fails loudly rather than '
            'hanging on another device that may have crashed mid-mint');
    expect(c.verbs.where((k) => k.key.startsWith('__nskey') == true), isEmpty);
  });

  test('the lease is stamped BEFORE the take goes out, not after', () async {
    // UC-B5.7 rests its safety on the DIRECTION of the error: the atServer
    // starts the ttl when it stores the record, at or after the moment this
    // client sent the request, so a deadline taken from the send makes the
    // client give up slightly EARLY. One taken from the reply would have it
    // believe it still held a lock the atServer had already released — and
    // publish over the enrollment that legitimately won the next election.
    const ttl = Duration(seconds: 20);
    const takeDelay = Duration(milliseconds: 400);
    final c = client(takeDelay: takeDelay);

    final before = DateTime.now();
    late DateTime deadline;
    final result = await MintLock(c.client)
        .withLock(nskeyMintLockKey(atSign, namespace, ttl: ttl), (lease) async {
      deadline = lease.expiresAt;
      return 'minted';
    });

    expect(result, 'minted',
        reason: 'the take succeeded, so the lease under '
            'test is a real one rather than a refusal path');
    expect(c.verbs.where((k) => k.key == '_nskeylock'), hasLength(1),
        reason: 'the control that the delay was actually paid: the take is '
            'the verb it was attached to, and it went out exactly once');

    // A deadline stamped from before the send is at most `before + ttl`; one
    // stamped from the reply is at least `before + takeDelay + ttl`, so the
    // bound sits between the two.
    expect(deadline.isBefore(before.add(ttl + takeDelay ~/ 2)), isTrue,
        reason: 'the deadline does NOT include the ${takeDelay.inMilliseconds}'
            'ms the take spent in flight — it was stamped before the request '
            'went out, which is the direction that errs early');
    expect(deadline.isAfter(before.add(ttl - takeDelay)), isTrue,
        reason: 'and it is not trivially early either: it is a full ttl from '
            'the send, so the assertion above is about WHERE the stamp was '
            'taken and not about the lease being short');
  });

  test('the keygen and the signature happen BEFORE the lock is taken',
      () async {
    // A mint lock is a window bounded by a ttl: everything done while holding
    // it is time in which no other enrollment of this atSign can mint and this
    // one can still lose its lease, so the section holds the writes that must
    // be serialised and as little else as possible.
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    final startedAt = DateTime.now();
    await ring.mintAndPublish(namespace);

    final lockTakenAt = c.verbTimes['_nskeylock'];
    final advertisedAt = c.verbTimes['__nskey'];
    expect(lockTakenAt, isNotNull,
        reason: 'the control: the lock take and the advertisement are the two '
            'verbs this measures between, so a fixture that recorded neither '
            'would make the comparison below vacuous');
    expect(advertisedAt, isNotNull);

    final beforeLock = lockTakenAt!.difference(startedAt);
    final inLock = advertisedAt!.difference(lockTakenAt);

    expect(inLock, lessThan(beforeLock),
        reason: 'more work happens before the lock than inside it. Under the '
            'previous arrangement the ratio is the other way round and by a '
            'wide margin — 53ms in the lock against 2.6ms before it — so this '
            'discriminates by roughly 20x in one direction and 8x in the '
            'other, which is far more than a loaded machine moves it. '
            'Reverting the hoist reddens this');
  });

  test('a mint that overruns its lease publishes nothing', () async {
    // The election bounds when the enrollments ATTEMPT, not how long the
    // winner TAKES: a slow winner would otherwise publish over the enrollment
    // that legitimately won the next election.
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client,
        mintLock: _SpentLeaseLock(c.client), privateFiling: await filing());

    await expectLater(
        ring.mintAndPublish(namespace),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('expired while this client was minting'))));
    expect(c.verbs.where((k) => k.key.startsWith('__nskey') == true), isEmpty,
        reason: 'the advertisement is what another enrollment would be '
            'overwritten by, so a holder whose lease has run out must not '
            'write it');
  });

  /// The winner's advertisement as it sits **on the atServer** — signed, so it
  /// goes through the same verify a peer's would.
  Future<String> publishedByAnother(
          MockAtClient client, XWingKeyPair winner) async =>
      AtClientEnvelopeSigner(client).wrapAndSignAndJsonEncode(
          NskeyAdvertisement.single(
            publicKey: winner.publicKeyBytes,
            alg: SecretSharingAlgos.xWing,
            suites:
                SecretSharingAlgos.openableSuitesFor(SecretSharingAlgos.xWing),
          ).toPayload(),
          type: EnvelopeType.nskeyRing);

  test('UC-G2.6 c6 · the added document is re-signed by the ADDING enrollment',
      () async {
    final c = client();
    // Same chops as the fixture, which serves one `_apsk` for every enrollment,
    // so this signature verifies while claiming a different kid.
    final other = MockAtClient();
    final otherSecondary = MockRemoteSecondary();
    final otherLookUp = MockAtLookUp();
    when(() => other.atChops).thenReturn(c.client.atChops);
    when(() => other.getCurrentAtSign()).thenReturn(atSign);
    when(() => other.getRemoteSecondary()).thenReturn(otherSecondary);
    when(() => otherSecondary.atLookUp).thenReturn(otherLookUp);
    when(() => otherLookUp.enrollmentId).thenReturn('enroll-minter');

    final xWing = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
    final minted = await xWing.keyPairFromSeed(xWing.newSeed());
    c.advertised[namespace] =
        await AtClientEnvelopeSigner(other).wrapAndSignAndJsonEncode(
            NskeyAdvertisement.single(
              publicKey: minted.publicKey,
              alg: SecretSharingAlgos.xWing,
              suites: SecretSharingAlgos.openableSuitesFor(
                  SecretSharingAlgos.xWing),
            ).toPayload(),
            type: EnvelopeType.nskeyRing);

    expect(
        SignedEnvelope.fromJson(
                jsonDecode(c.advertised[namespace]!) as Map<String, dynamic>)
            .signerEnrollmentId,
        'enroll-minter',
        reason: 'the control: the generation starts out signed by somebody '
            'else, so the assertion below measures a change rather than a '
            'constant');

    // This client implements an algorithm the generation lacks, so it has
    // something to add.
    when(() => c.client.getPreferences()).thenReturn(AtClientPreference(
        keyEstablishmentAlgorithms: const [
          SecretSharingAlgos.xWing,
          SecretSharingAlgos.mlKem1024
        ],
        posture: PqPosture.pqReady));

    final added = await PublishedNskeyKeyRing(c.client).add(namespace);
    expect(added, isNotNull, reason: 'the add had work to do');

    expect(
        SignedEnvelope.fromJson(
                jsonDecode(c.values['__nskey']!) as Map<String, dynamic>)
            .signerEnrollmentId,
        'enroll-a',
        reason: 'c6: the republished document is signed by the ADDING '
            'enrollment. A reader resolves the signer from the envelope\'s own '
            'kid and verifies against THAT enrollment\'s _apsk, so a document '
            'still claiming the minter would be checked against the wrong key');
  });

  test('every advertisement read on the mint path goes to the atServer',
      () async {
    // NOTE: the mint path only — `currentPublic`, which every put reaches
    // through `CkManager.ensureCurrent`, stays local-first on purpose.
    final c = client();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());

    await ring.mintAndPublish(namespace);

    expect(c.advertisementReads, isNotEmpty,
        reason: 'the mint asks whether a generation is already published');
    expect(c.advertisementReads.map((o) => o?.useRemoteAtServer),
        everyElement(isTrue),
        reason: 'a local-first read answers out of storage that a sibling '
            'enrollment\'s publication has not synced into yet, and reading '
            'that absence as a cold start is what publishes a second key over '
            'the first');
  });

  test('the loser of the race adopts the winner\'s advertisement', () async {
    final c = client(lockAlreadyHeld: true);
    final winner = await XWingKeyPair.generate();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());
    // On the atServer, not in this client's memory: a fixture that seeded it
    // locally would be testing the wrong absence.
    c.advertised[namespace] = await publishedByAnother(c.client, winner);

    final adopted = await ring.mintAndPublish(namespace);

    expect(adopted.nskeyKid, nskeyKidOf(winner.publicKeyBytes),
        reason: 'minting a second key would rotate the first out from under '
            'every peer that had already fetched it');
    expect(c.verbs.where((k) => k.key.startsWith('__nskey') == true), isEmpty,
        reason: 'and the loser publishes nothing at all');
  });

  test('a winner that published while this client took the lock is adopted',
      () async {
    // This client WINS the race, so nothing refuses it — but a sibling
    // published in the window between the decision to mint and the lock being
    // taken, and the record is mutable.
    final c = client();
    final winner = await XWingKeyPair.generate();
    final ring = PublishedNskeyKeyRing(c.client, privateFiling: await filing());
    c.advertised[namespace] = await publishedByAnother(c.client, winner);

    final adopted = await ring.mintAndPublish(namespace);

    expect(adopted.nskeyKid, nskeyKidOf(winner.publicKeyBytes),
        reason: 'a different kid means this client minted its own generation '
            'over the sibling\'s, which is the overwrite the re-read under the '
            'lock exists to prevent');
    expect(c.verbs.where((k) => k.key == '_nskeylock'), hasLength(1),
        reason: 'the lock was taken — this client is the winner, and the '
            're-read under it is what stops it overwriting the sibling');
    expect(c.verbs.where((k) => k.key.startsWith('__nskey') == true), isEmpty,
        reason: 'and nothing is published over the generation already there');
  });
}
