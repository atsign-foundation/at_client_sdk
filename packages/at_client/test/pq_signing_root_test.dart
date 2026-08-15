import 'dart:convert';
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo;
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {
}

/// The atSign's root of trust.
///
/// Every property here is about the same thing: the record is immutable and
/// the root never rotates, so a mistake at mint is permanent. There is no
/// second attempt, no rotation to recover with, and two roots would leave half
/// an atSign's enrollments chaining to one the other half rejects.
/// Generation 1 of a root filed under the algorithm this build mints.
final rootSlot1 =
    '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1';

void main() {
  const atSign = '@alice';

  setUpAll(() {
    registerFallbackValue(FakeUpdateVerbBuilder());
    registerFallbackValue(FakeAtKey());
  });

  ({MockAtClient client, List<UpdateVerbBuilder> published}) client(
      {bool createRefused = false,
      String? enrollmentId = 'enrollment-1',
      Uint8List? publishedRoot,
      bool rootUnreadable = false}) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    // The signing-root pull reads the enrollment id off the lookup to tell an
    // APKAM enrollment from a client using the atSign's own keys.
    final lookup = MockAtLookUp();
    when(() => secondary.atLookUp).thenReturn(lookup);
    when(() => lookup.enrollmentId).thenReturn(enrollmentId);
    final published = <UpdateVerbBuilder>[];
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    // The published-record read: confirmed absent unless the fixture holds
    // one, unreadable when asked to be.
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
      if (rootUnreadable) {
        throw AtLookUpException('AT0011', 'the record cannot be read');
      }
      if (publishedRoot == null) {
        throw KeyNotFoundException('public:pq_signing_root$atSign not found');
      }
      return Future.value(AtValue()
        ..value = jsonEncode(apskAdvertisement(keys: [
          ApskSigningKey.forPublicKey(
              alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(publishedRoot))
        ])));
    });
    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as UpdateVerbBuilder;
      published.add(builder);
      if (createRefused) {
        throw AtLookUpException(
            'AT0023', 'Immutable records may not be updated');
      }
      return 'data:1';
    });
    return (client: atClient, published: published);
  }

  Future<InMemoryAtKeysIo> keysIo() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return io;
  }

  test('a fully privileged enrollment mints it, private filed first', () async {
    final c = client();
    final io = await keysIo();

    final publicKey = await PqSigningRoot(c.client, keysIo: io)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(publicKey, isNotNull);
    final filed = (await io.read(atSign))
        .getAtSignKey(
            rootSlot1, CryptographicKeyType.privateSigning);
    expect(filed, isNotNull,
        reason: 'the record is immutable and the root never rotates, so a '
            'published root whose private did not survive can never be '
            'replaced');
    expect(filed!.keyAlgorithmType, KeyAlgorithmType.mlDsa65);

    final record = c.published.single;
    expect(record.atKey.key, PqSigningRoot.recordName);
    expect(record.atKey.metadata.immutable, isTrue,
        reason: 'create-once is what guarantees exactly one root exists — two '
            'would be unrecoverable, not merely untidy');
    expect(record.atKey.metadata.isPublic, isTrue);
    expect(jsonDecode(record.value!)['keys'], hasLength(1));
  });

  test('the published record emits its exact wire shape — raw literals',
      () async {
    // Emitter pin (frozen forever): the record is immutable create-once and
    // the root never rotates, so this byte shape is permanent on every atSign
    // that holds one. Raw strings deliberately — the sibling tests assert
    // through PqSigningRoot's own constants, which follow a changed value.
    final c = client();

    await PqSigningRoot(c.client, keysIo: await keysIo())
        .mintIfAbsent(isFullyPrivileged: true);

    final record = c.published.single;
    expect(record.atKey.toString(), 'public:pq_signing_root@alice');
    final body = jsonDecode(record.value!) as Map<String, dynamic>;
    expect(body.keys.toList(), ['v', 'keys'],
        reason: 'no `successor`: it was reserved for a rotation pointer and '
            'could never hold one, so decisions 101 deleted it rather than '
            'implementing it');
    expect(body['v'], 1);
    final entry = (body['keys'] as List).single as Map<String, dynamic>;
    expect(entry.keys.toList(), ['kid', 'use', 'alg', 'pub'],
        reason: 'the `_apsk` entry shape, because the root IS an ordinary '
            'signing key. `status` is absent while the key is active and '
            'appears only once one is retired');
    expect(entry['use'], 'sign',
        reason: 'accurate rather than ceremonial — nothing is ever '
            'encapsulated to the signing root');
    expect(entry['alg'], 'mldsa65',
        reason: 'ONE spelling now. This asserted the hyphenated "ml-dsa-65" '
            'until decisions 101; nothing was released carrying either, so '
            'the two-spellings-are-frozen argument was the greenfield rule '
            'in disguise');
    expect(entry['kid'], isA<String>(),
        reason: 'derived from the key material by the composer, never '
            'supplied — the key identifier a root link needs in order to say '
            'WHICH root signed it');
    expect(base64Decode(entry['pub'] as String), hasLength(1952),
        reason: 'a raw ML-DSA-65 public key, not PEM');
  });

  test('a restricted enrollment mints nothing', () async {
    final c = client();
    final io = await keysIo();

    expect(
        await PqSigningRoot(c.client, keysIo: io)
            .mintIfAbsent(isFullyPrivileged: false),
        isNull);
    expect(c.published, isEmpty,
        reason: 'an enrollment restricted to one namespace has no business '
            'minting the key that vouches for every other enrollment');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test('a mint that cannot file its private publishes nothing', () async {
    final c = client();

    await expectLater(
        // Key storage with nothing written for this atSign: the read throws.
        PqSigningRoot(c.client, keysIo: InMemoryAtKeysIo())
            .mintIfAbsent(isFullyPrivileged: true),
        throwsA(isA<StateError>()));
    expect(c.published, isEmpty,
        reason: 'an immutable record cannot be retried with a different key, '
            'so publishing before the private is safe would burn the one '
            'chance this atSign gets');
  });

  test('losing the create is not an error, and retires the losing pair',
      () async {
    final c = client(createRefused: true);
    final io = await keysIo();
    final root = PqSigningRoot(c.client, keysIo: io);

    expect(await root.mintIfAbsent(isFullyPrivileged: true), isNull,
        reason: 'the atServer refusing a second create IS the create-once '
            'guarantee working — this client waits to be given the root '
            'rather than treating it as a failure');

    expect(await root.privateHalf(atSign), isNull,
        reason: 'the losing pair corresponds to nothing any verifier ever '
            'saw. Left active it would read as "already holding the root" '
            'forever — the pull\'s cheapest guard — and block the one heal '
            'a loser has');
    final materials = (await io.read(atSign)).keys;
    expect(materials, isNotEmpty,
        reason: 'key material is never removed, only retired — the losing '
            'bytes stay in the file, marked dead');
    expect(materials.map((m) => m.status).toSet(), {KeyPartStatus.dead});

    // The heal the retirement re-opens: with nothing active held, the pull
    // asks the namespace again.
    final broadcast = _RecordingSharing();
    final asked = await root.requestPrivateIfAbsent(
      isFullyPrivileged: () async => true,
      sharing: broadcast,
      namespace: 'buzz',
    );
    expect(asked, greaterThan(0),
        reason: 'this is what the rollback exists for: a loser that still '
            'reads as holding the root never asks, and the root is immutable '
            'and never rotates, so nothing else would ever repair it');
  });

  group('when the publish call fails but its outcome is unknown', () {
    // The refusal of a second create and a dropped connection on a write that
    // LANDED throw the same way, and they need opposite handling. Getting the
    // second one wrong is unrecoverable: retiring the pair for a root this
    // client did publish leaves the atSign with an immutable, non-rotating
    // record whose private nobody holds.

    test('a create that actually landed is kept, not retired', () async {
      // The record the failed call wrote is whatever key this mint generates,
      // so serve it back by capturing what was published.
      final atClient = MockAtClient();
      final secondary = MockRemoteSecondary();
      final lookup = MockAtLookUp();
      when(() => secondary.atLookUp).thenReturn(lookup);
      when(() => lookup.enrollmentId).thenReturn('enrollment-1');
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
      String? publishedValue;
      when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer((inv) async {
        publishedValue =
            (inv.positionalArguments[0] as UpdateVerbBuilder).value;
        // Landed, then the connection died before the ack.
        throw AtLookUpException('AT0011', 'connection closed');
      });
      when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
        if (publishedValue == null) {
          throw KeyNotFoundException('not found');
        }
        return Future.value(AtValue()..value = publishedValue);
      });

      final io = await keysIo();
      final root = PqSigningRoot(atClient, keysIo: io);

      final minted = await root.mintIfAbsent(isFullyPrivileged: true);

      expect(minted, isNotNull,
          reason: 'the record IS published and this client holds its private, '
              'so it is the minter — reporting a loss here would tell the '
              'caller the opposite of what happened');
      expect(await root.privateHalf(atSign), isNotNull,
          reason: 'and the private must survive: the root is immutable and '
              'never rotates, so retiring it would brick the atSign for good');
    });

    test('an unreadable record after a failed publish keeps the pair',
        () async {
      final atClient = MockAtClient();
      final secondary = MockRemoteSecondary();
      final lookup = MockAtLookUp();
      when(() => secondary.atLookUp).thenReturn(lookup);
      when(() => lookup.enrollmentId).thenReturn('enrollment-1');
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
      var reads = 0;
      when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
        reads++;
        // The absence check at the start of the mint succeeds; the
        // reconciliation read after the failed publish does not.
        if (reads == 1) throw KeyNotFoundException('not found');
        throw AtLookUpException('AT0011', 'cannot read');
      });
      when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer((_) async =>
              throw AtLookUpException('AT0011', 'connection closed'));

      final io = await keysIo();
      final root = PqSigningRoot(atClient, keysIo: io);

      expect(await root.mintIfAbsent(isFullyPrivileged: true), isNull,
          reason: 'it cannot claim to have minted what it cannot confirm');
      expect(await root.privateHalf(atSign), isNotNull,
          reason: 'but it must NOT retire on an unknown outcome: a later '
              'start reconciles the held pair against the record, and '
              'retiring a private whose record landed cannot be undone');
    });
  });

  test('a published root means no mint, with nothing generated or stored',
      () async {
    final pair = await MlDsa65PureDartAlgo().generateKeyPair();
    final c = client(publishedRoot: pair.publicKey);
    final io = await keysIo();

    expect(
        await PqSigningRoot(c.client, keysIo: io)
            .mintIfAbsent(isFullyPrivileged: true),
        isNull);
    expect(c.published, isEmpty,
        reason: 'a create against an existing immutable record would be '
            'refused anyway; checking first keeps the common late-arrival '
            'case from filing a pair only to retire it');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  // DELETED 2026-08-15: 'a root published before the shape was settled is
  // still read'. It asserted the bare-base64 reader, which decisions 101
  // removed. Its premise — that already-published roots can never be
  // rewritten and so must be tolerated forever — was the greenfield rule in
  // disguise: nothing is released, so every atSign holding a root is ours.

  test('an unreadable root record aborts the mint rather than racing it',
      () async {
    final c = client(rootUnreadable: true);
    final io = await keysIo();

    await expectLater(
        PqSigningRoot(c.client, keysIo: io)
            .mintIfAbsent(isFullyPrivileged: true),
        throwsA(isA<AtLookUpException>()),
        reason: 'absent and unreadable are different answers, and with an '
            'immutable record at stake a client that cannot tell them apart '
            'must not guess');
    expect(c.published, isEmpty);
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test(
      'a held private that does not correspond to the published root is '
      'retired, and the real one can then be filed', () async {
    final minted = await MlDsa65PureDartAlgo().generateKeyPair();
    final poisoned = await MlDsa65PureDartAlgo().generateKeyPair();
    final c = client(publishedRoot: minted.publicKey);
    final io = await keysIo();
    final root = PqSigningRoot(c.client, keysIo: io);

    // The pre-rollback loser's state: an active private filed by a lost
    // create, corresponding to nothing published.
    expect(await root.store(atSign, poisoned.secretKey), isTrue);

    expect(await root.mintIfAbsent(isFullyPrivileged: true), isNull);
    expect(await root.privateHalf(atSign), isNull,
        reason: 'reconciling against the published record is the only event '
            'that can ever notice this state — the poisoned bytes sign '
            'probes happily, they just verify against nothing anyone '
            'published');

    // The heal: the real private now files beside the dead slot…
    expect(
        await root.file(
            atSign,
            Secret(
                namespace: 'buzz',
                name: PqSigningRoot.secretName,
                value: base64Encode(minted.secretKey))),
        isTrue);
    // …and is what readers see.
    expect(await root.privateHalf(atSign), minted.secretKey);
  });

  test('a crash between filing and publishing republishes the held pair',
      () async {
    final c = client();

    // The state a crash between filing and publishing leaves behind: both
    // halves filed and active, nothing published. Built directly — the crash
    // itself cannot be staged through the API, which is rather the point.
    final freshIo = await keysIo();
    final held = await MlDsa65PureDartAlgo().generateKeyPair();
    final keys = await freshIo.read(atSign);
    final createdAt = DateTime.now().toUtc();
    keys.addKey(AtKeysMaterial(
      keyId: rootSlot1,
      keyPartType: CryptographicKeyType.privateSigning,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: AtBytes(held.secretKey),
      createdAt: createdAt,
    ));
    keys.addKey(AtKeysMaterial(
      keyId: rootSlot1,
      keyPartType: CryptographicKeyType.publicVerification,
      keyAlgorithmType: KeyAlgorithmType.mlDsa65,
      bytes: AtBytes(held.publicKey),
      createdAt: createdAt,
    ));
    await freshIo.flush(atSign.toAtsign(), keys);

    final republished = await PqSigningRoot(c.client, keysIo: freshIo)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(republished, held.publicKey,
        reason: 'minting a fresh pair here would publish a public whose '
            'private was discarded — an immutable record nobody holds the '
            'key to, permanently. The held pair is the only safe thing to '
            'publish');
    final record = jsonDecode(c.published.single.value!) as Map;
    final entry = (record['keys'] as List).single as Map;
    expect(entry['pub'], base64Encode(held.publicKey),
        reason: 'recovery republishes the HELD public half, not a fresh one');
    expect(entry['alg'], PqSigningRoot.rootKeyAlgo.name);
    expect(entry['use'], 'sign');
    expect(entry['kid'], isNotNull,
        reason: 'composed through the `_apsk` advertisement codec, which '
            'derives the kid from the key material');
    expect((await freshIo.read(atSign)).keys, hasLength(2),
        reason: 'recovery publishes what is already filed — it must not '
            'add or replace material');
  });

  test(
      'a held private with no public half and no record is retired, '
      'and a fresh root minted', () async {
    final c = client();
    final io = await keysIo();
    final root = PqSigningRoot(c.client, keysIo: io);

    // The pre-both-halves file shape: a private alone, nothing published.
    final orphan = await MlDsa65PureDartAlgo().generateKeyPair();
    expect(await root.store(atSign, orphan.secretKey), isTrue);

    final minted = await root.mintIfAbsent(isFullyPrivileged: true);

    expect(minted, isNotNull);
    expect(minted, isNot(orphan.publicKey),
        reason: 'the orphan\'s public half cannot be derived from its '
            'private, so it cannot be republished; nothing was ever '
            'published for it, so no verifier ever accepted anything '
            'against it and a fresh mint loses nothing');
    final active = await root.privateHalf(atSign);
    expect(active, isNotNull);
    expect(active, isNot(orphan.secretKey));
  });

  test('a root slot of another algorithm is still a root slot', () async {
    // What rotatability rests on, and it is the READER half: a slot is
    // recognised by its role, never by one algorithm. A build that only
    // matches `root:mldsa65:` can find no successor of any other algorithm,
    // which would pin the atSign to ML-DSA-65 by accident of its reader rather
    // than by any decision — and would do it silently, since a keyfile holding
    // such a slot simply reads as holding no root at all.
    //
    // The token is deliberately one this build knows nothing about:
    // `KeyAlgorithmType.known` exists for warn-level tooling and explicitly
    // does not gate what may be filed, so a reader that recognised only known
    // tokens would be a second, undocumented gate.
    const laterAlgo = 'some-later-signing-algo';
    final c = client();
    final io = await keysIo();
    final keys = await io.read(atSign);
    final held = Uint8List.fromList([7, 8, 9]);
    keys.addKey(AtKeysMaterial(
      keyId: '${PqSigningRoot.keyIdPrefixFor(laterAlgo)}1',
      keyPartType: CryptographicKeyType.privateSigning,
      keyAlgorithmType: laterAlgo,
      bytes: AtBytes(held),
      createdAt: DateTime.now().toUtc(),
    ));
    await io.flush(atSign.toAtsign(), keys);

    expect(await PqSigningRoot(c.client, keysIo: io).privateHalf(atSign), held,
        reason: 'the slot is root:<any algorithm>:<generation>, so a private '
            'filed under a later algorithm is the root private');
  });

  test('generations count per algorithm, so a successor starts at 1', () async {
    // The counter is per `root:<algo>:`, not per role: two algorithms each
    // begin at generation 1 rather than the second one inheriting the first's
    // count. Filed in the same document so the two lines are visibly
    // independent.
    final io = await keysIo();
    final keys = await io.read(atSign);
    keys.addKey(AtKeysMaterial(
      keyId: '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1',
      keyPartType: CryptographicKeyType.privateSigning,
      keyAlgorithmType: PqSigningRoot.rootKeyAlgoToken,
      bytes: AtBytes(Uint8List.fromList([1])),
      createdAt: DateTime.now().toUtc(),
    ));

    expect(
        keys.nextAtSignGeneration(
            PqSigningRoot.keyIdRole, PqSigningRoot.rootKeyAlgoToken),
        2);
    expect(keys.nextAtSignGeneration(PqSigningRoot.keyIdRole, 'another-algo'),
        1);
  });

  group('reconciling a held private against the published root', () {
    test('a private that corresponds to nothing published is retired',
        () async {
      final minted = await MlDsa65PureDartAlgo().generateKeyPair();
      final poisoned = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoot: minted.publicKey);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, poisoned.secretKey), isTrue);

      expect(await root.reconcileHeldPrivate(atSign), isTrue);
      expect(await root.privateHalf(atSign), isNull,
          reason: 'while it stays active nothing repairs it: the pull\'s '
              'cheapest guard reads "already holding it" so this enrollment '
              'never asks, and a correct private conveyed to it would be '
              'dropped by store() for the same reason');

      // And the repair it re-opens actually works.
      expect(
          await root.file(
              atSign,
              Secret(
                  namespace: 'buzz',
                  name: PqSigningRoot.secretName,
                  value: base64Encode(minted.secretKey))),
          isTrue);
      expect(await root.privateHalf(atSign), minted.secretKey);
    });

    test('the corresponding private is left alone', () async {
      final minted = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoot: minted.publicKey);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      await root.store(atSign, minted.secretKey);

      expect(await root.reconcileHeldPrivate(atSign), isFalse);
      expect(await root.privateHalf(atSign), minted.secretKey,
          reason: 'the ordinary case is a holder holding the right key, and '
              'retiring it would destroy the atSign\'s only copy');
    });

    test('with no root published, a held private is left alone', () async {
      final held = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      await root.store(atSign, held.secretKey);

      expect(await root.reconcileHeldPrivate(atSign), isFalse);
      expect(await root.privateHalf(atSign), isNotNull,
          reason: 'a private filed before its record is published is the '
              'ordinary crash-recovery state — the mint files durably first '
              'on purpose, and that pair is exactly what recovery republishes');
    });

    test('an unreadable record retires nothing', () async {
      final held = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(rootUnreadable: true);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      await root.store(atSign, held.secretKey);

      expect(await root.reconcileHeldPrivate(atSign), isFalse);
      expect(await root.privateHalf(atSign), isNotNull,
          reason: 'an unreadable record is no evidence at all, and retiring '
              'the atSign\'s root private cannot be undone');
    });
  });

  group('filing an arriving private', () {
    test('garbage that cannot be the root private is refused', () async {
      final minted = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoot: minted.publicKey);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      expect(
          await root.file(
              atSign,
              Secret(
                  namespace: 'buzz',
                  name: PqSigningRoot.secretName,
                  value: base64Encode(List<int>.filled(32, 7)))),
          isFalse,
          reason: 'the root is immutable and never rotates, so filing the '
              'wrong bytes sticks forever — and a 32-byte buffer cannot '
              'sign anything the published root verifies');
      expect((await io.read(atSign)).keys, isEmpty);
    });

    test('a real key that is not the root private is refused', () async {
      final minted = await MlDsa65PureDartAlgo().generateKeyPair();
      final other = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoot: minted.publicKey);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      expect(
          await root.file(
              atSign,
              Secret(
                  namespace: 'buzz',
                  name: PqSigningRoot.secretName,
                  value: base64Encode(other.secretKey))),
          isFalse,
          reason: 'shape is not correspondence: a well-formed ML-DSA key '
              'that signs valid signatures is still the wrong key if the '
              'published root does not verify them');
      expect(await root.privateHalf(atSign), isNull);
    });

    test('the corresponding private is filed', () async {
      final minted = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoot: minted.publicKey);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      expect(
          await root.file(
              atSign,
              Secret(
                  namespace: 'buzz',
                  name: PqSigningRoot.secretName,
                  value: base64Encode(minted.secretKey))),
          isTrue);
      expect(await root.privateHalf(atSign), minted.secretKey);
    });

    test('with no root published, nothing is filed', () async {
      final other = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      expect(
          await root.file(
              atSign,
              Secret(
                  namespace: 'buzz',
                  name: PqSigningRoot.secretName,
                  value: base64Encode(other.secretKey))),
          isFalse,
          reason: 'a private with no published record has nothing to '
              'correspond to — the minter publishes before conveying, so an '
              'arrival in this state is wrong by construction');
      expect((await io.read(atSign)).keys, isEmpty);
    });

    test('an unreadable record defers filing rather than guessing', () async {
      final other = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(rootUnreadable: true);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      expect(
          await root.file(
              atSign,
              Secret(
                  namespace: 'buzz',
                  name: PqSigningRoot.secretName,
                  value: base64Encode(other.secretKey))),
          isFalse,
          reason: 'refusing is safe: the keyfile stays without a root '
              'private, so the every-start pull asks again and a later '
              'answer heals it — filing unverified bytes would stick');
      expect((await io.read(atSign)).keys, isEmpty);
    });
  });

  group('requesting the private when this enrollment has none', () {
    /// Records what was broadcast without doing any real sharing.
    _RecordingSharing sharing() => _RecordingSharing();

    test('a privileged enrollment that holds nothing asks the namespace',
        () async {
      final io = await keysIo();
      final broadcast = sharing();

      final asked = await PqSigningRoot(client().client, keysIo: io)
          .requestPrivateIfAbsent(
        isFullyPrivileged: () async => true,
        sharing: broadcast,
        namespace: 'buzz',
      );

      expect(asked, 2,
          reason: 'it must reach the holders in the namespace; '
              'the root carries no namespace of its own, so this broadcast is the '
              'only route left to an enrollment that missed the conveyance');
      expect(broadcast.requests, hasLength(1));
      expect(broadcast.requests.single.namespace, 'buzz');
      expect(broadcast.requests.single.names, [PqSigningRoot.secretName],
          reason: 'it asks for the root by name rather than pulling whatever '
              'holders happen to have');
    });

    test('an enrollment that already holds it asks nobody', () async {
      final io = await keysIo();
      final atClient = client().client;
      final root = PqSigningRoot(atClient, keysIo: io);
      await root.store(atSign, Uint8List.fromList(List<int>.filled(32, 3)));

      final broadcast = sharing();
      expect(
          await root.requestPrivateIfAbsent(
            isFullyPrivileged: () async => true,
            sharing: broadcast,
            namespace: 'buzz',
          ),
          0);
      expect(broadcast.requests, isEmpty,
          reason: 'this runs on every start; a client that broadcast each time '
              'regardless would put a fan-out on the wire per launch per '
              'device, asking for something it is already holding');
    });

    test('a restricted enrollment asks nobody', () async {
      final io = await keysIo();
      final broadcast = sharing();

      expect(
          await PqSigningRoot(client().client, keysIo: io)
              .requestPrivateIfAbsent(
            isFullyPrivileged: () async => false,
            sharing: broadcast,
            namespace: 'buzz',
          ),
          0);
      expect(broadcast.requests, isEmpty,
          reason: 'only a fully privileged enrollment may hold the key that '
              'vouches for every enrollment on the atSign. Asking would be '
              'refused anyway, and asking announces to every holder that '
              'something unentitled is looking for it');
    });

    test('a client authenticating with the atSign\'s own keys asks nobody',
        () async {
      final io = await keysIo();
      // No enrollment id on the lookup: the atSign itself, not an enrollment.
      final broadcast = _RecordingSharing();

      expect(
          await PqSigningRoot(client(enrollmentId: null).client, keysIo: io)
              .requestPrivateIfAbsent(
            isFullyPrivileged: () async => true,
            sharing: broadcast,
            namespace: 'buzz',
          ),
          0);
      expect(broadcast.requests, isEmpty,
          reason: 'such a client CANNOT ask — enumerating holders goes through '
              'enroll:listns, which the atServer refuses without APKAM '
              'authentication — and has no reason to: it is the atSign, so its '
              'route to a missing root is to mint one. Without this guard '
              'every legacy PKAM client broadcasts, is refused, and logs a '
              'warning on each start');
    });

    test('the privilege check is not consulted before the cheaper one',
        () async {
      final io = await keysIo();
      final atClient = client().client;
      final root = PqSigningRoot(atClient, keysIo: io);
      await root.store(atSign, Uint8List.fromList(List<int>.filled(32, 3)));

      var privilegeChecked = false;
      await root.requestPrivateIfAbsent(
        isFullyPrivileged: () async {
          privilegeChecked = true;
          return true;
        },
        sharing: sharing(),
        namespace: 'buzz',
      );

      expect(privilegeChecked, isFalse,
          reason: 'resolving privilege costs a round trip to the enrollment '
              'record. Holding the private already settles the question, and '
              'that is the case on essentially every start of every client');
    });
  });
}

/// Captures broadcasts instead of sending them, so the guards can be asserted
/// on what reached the wire rather than on a return value the method could
/// produce without doing anything.
class _RecordingSharing extends Fake implements PairwiseSecretSharing {
  final List<({String namespace, List<String>? names})> requests = [];

  @override
  Future<int> requestSecretsFromNamespace(
    String namespace, {
    List<String>? names,
    String? namePrefix,
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    requests.add((namespace: namespace, names: names));
    return 2;
  }
}
