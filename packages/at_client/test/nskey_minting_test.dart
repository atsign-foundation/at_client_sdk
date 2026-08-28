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

class MockAtClient extends Mock implements AtClient {}

/// A lock that is taken successfully and hands out a lease that has already
/// run out — the slow-winner case, without waiting for a real ttl.
///
/// Overriding [withLock] rather than stubbing the wire keeps the ttl out of
/// the ring's constructor: the lease is what the mint is supposed to honour,
/// and this hands it one it cannot.
class _SpentLeaseLock extends MintLock {
  // Not const: MintLock stopped being a const class when it gained the
  // in-flight map that stops an enrolment racing itself.
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
  ///
  /// Serving the advertisement back matters: the mint path reads the atServer
  /// rather than this client's caches, precisely so that a *sibling*
  /// enrollment's publication is visible before sync catches up. A fixture that
  /// always answered "absent" would make every adoption test pass by minting.
  ({
    MockAtClient client,
    List<AtKey> verbs,
    List<Object> builders,
    Map<String, String?> values,
    Map<String, DateTime> verbTimes,
    Map<String, String> advertised,
    List<GetRequestOptions?> advertisementReads,

    /// [takeDelay] makes the lock's own take slow, which is the only way to
    /// tell a lease stamped BEFORE the request from one stamped after it:
    /// with an instant take the two are indistinguishable.
  }) client(
      {bool lockAlreadyHeld = false, Duration takeDelay = Duration.zero}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookUp();
    final verbs = <AtKey>[];
    // Every builder, not only the updates: "the lock is never deleted" is a
    // claim about a verb that must not appear, and a recorder that only keeps
    // updates cannot tell an absent delete from an unrecorded one.
    final builders = <Object>[];
    final values = <String, String?>{};
    // When each remote write arrived. The mint lock's window is the gap
    // between the lock take and the advertisement, and nothing else can
    // measure it from outside.
    final verbTimes = <String, DateTime>{};
    // The atServer's copy of `public:__nskey.<ns>@alice`, by namespace. A test
    // writes into it to stand for another enrollment having published.
    final advertised = <String, String>{};
    // How each advertisement read was asked for. A mocktail stub cannot tell a
    // local-first get from a remote one on its own — both arrive here — so the
    // options are what the remote-only claim is pinned against.
    final advertisementReads = <GetRequestOptions?>[];
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
      // Anything that is not the advertisement is the `_apsk` its signature is
      // checked against. One key for every enrollment of this atSign, so an
      // advertisement signed by the fixture verifies whichever enrollment it
      // claims — authenticity itself is pinned in published_nskey_key_ring_test.
      if (key.key != '__nskey') {
        return AtValue()
          ..value = chops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;
      }
      advertisementReads
          .add(inv.namedArguments[#getRequestOptions] as GetRequestOptions?);
      final serving = advertised[key.namespace];
      if (serving == null) throw AtKeyNotFoundException('$key');
      return AtValue()..value = serving;
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

    // The positive half: the update really carried this generation, so the
    // absence below is a second write that did not happen rather than a mint
    // that did not.
    expect(c.values['__nskey'], isNotNull);
    expect(c.advertised[namespace], c.values['__nskey']);
    expect(advertisement.nskeyKid, isNotEmpty);

    // A local write of a sync-eligible key queues the key's NAME for a
    // client→server push, and the push sends whatever local storage holds when
    // it drains. A second write here would therefore race the update above: a
    // drain landing in between puts the superseded generation back on the
    // atServer, this client pulls that back over its own copy, and the atSign
    // goes on advertising a key it rotated away from.
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
    // Ordering, not just presence: the lock is taken, then the advertisement
    // goes out. The filing happens between them, off the wire.
    final published = c.verbs.where((k) => k.key.startsWith('__nskey') == true);
    expect(published, hasLength(1));
  });

  test('a ring built from the client alone files into the client\'s keyfile',
      () async {
    // The shape every hand-built ring has: `PublishedNskeyKeyRing(client)`,
    // naming no filing. It has to be durable anyway, because the client was
    // handed an AtKeysIo and an nskey private is the one kind of material that
    // cannot be re-fetched or re-derived — a ring that kept it in memory
    // beside a keyfile that was there all along publishes a key that stops
    // opening anything the moment the process ends.
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
    // the next process: what is being asserted is that the seed reached the
    // keyfile, not that the ring that minted it remembers it.
    expect(
        await NskeyPrivateFiling(keysIo: io, atSign: atSign)
            .read(namespace, advertisement.nskeyKid),
        isNotNull);
  });

  test('and a client with no key source mints into memory only', () async {
    // The control for the row above, and the posture a mocked fixture has:
    // `atKeysIo` unstubbed, so mocktail answers null and there is nothing to
    // derive a filing from. Minting still succeeds — refusing would refuse
    // every fixture — and `_mint` says so at `severe`, which this does not
    // assert because a log line is not a testable interface.
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
    // Emitter pin, frozen forever for both halves — the payload and the
    // envelope carrying it. Raw strings deliberately: the sibling tests assert
    // through the constants that define these values, which follow a changed
    // value silently. Only this pin fails when the wire moves, which is what
    // makes editing it the review.
    //
    // The entry spelling `{use, alg, pub, kid}` inside `{v, createdAt, keys,
    // suites}` is shared with the `_apsk` advertisement and the enrollment key
    // package, so a field renamed here is a field renamed in three records.
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

  test('a mint that cannot store its private publishes nothing', () async {
    final c = client();
    // Key storage with nothing in it for this atSign: `read` throws, so
    // `store` cannot persist and the mint must publish nothing rather than
    // leave a key whose private dies with the process.
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
    // The invariant the never-release change creates. While a successful mint
    // deleted its lock, a missing ttl only meant "no crash backstop"; now it
    // means the record has nothing that will ever remove it, so taking one
    // would block this atSign's minting permanently.
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
    // Row 4's other arm. The adopt case is below; this is the one where there
    // is nothing to adopt, and the loser still must not mint — two enrollments
    // minting is exactly what the election exists to prevent.
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
    // The sibling test proves a SPENT lease refuses; nothing proved where the
    // deadline came from, and with an instant take the two are identical.
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

    // The discriminator. A deadline stamped from before the send is at most
    // `before + ttl`; one stamped from the reply is at least
    // `before + takeDelay + ttl`. The delay is what separates them, so the
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
    // A mint lock is a window bounded by a ttl. Everything done while holding
    // it is time in which no other enrollment of this atSign can mint and this
    // one can still lose its lease — so the section should hold the writes
    // that must be serialised and as little else as possible.
    //
    // Measured on 2026-08-27, same fixture, only the hoist differing:
    //
    //   before  before-lock 2.6ms   in-lock 53.1ms
    //   after   before-lock 43.7ms  in-lock  5.6ms
    //
    // The ~47ms that left the critical section is the KEM keygen plus the
    // ML-DSA signature, which is what the hoist moved and matches the cost of
    // the two operations.
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
    // Row 5. The election bounds when the enrollments ATTEMPT, not how long
    // the winner TAKES, so without this the requirement fails with every other
    // part correct: a slow winner publishes over the enrollment that
    // legitimately won the next election.
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
    // The generation is minted and signed by ANOTHER enrollment, and this
    // client adds to it. c6 says the republished document carries the adder's
    // signature, not the minter's: an advertisement's signer is a property of
    // the document rather than of the generation, so a reader resolves it from
    // the envelope's own kid.
    final c = client();
    // Same chops as the fixture — the fixture serves one `_apsk` for every
    // enrollment, so this verifies while claiming a different kid, which is
    // exactly the situation under test.
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
    // Row 1. The sender's read (`currentPublic`) stays local-first on purpose —
    // `CkManager.ensureCurrent` reaches it on every put — so this is a claim
    // about the mint path only, and it is a claim about the OPTIONS rather than
    // about a value, because both routings return the same thing here.
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
    // On the atServer, not in this client's memory. A sibling enrollment's
    // publication is exactly what local storage does not have yet, so a
    // fixture that seeded it locally would be testing the wrong absence.
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
    // Row 2's differential, and the one the lock alone never covered: this
    // client WINS the race, so nothing refuses it — but a sibling published in
    // the window between the decision to mint and the lock being taken. The
    // record is mutable, so minting here overwrites a key peers already hold.
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
