import 'dart:async' show FutureOr;
import 'dart:convert';
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show pqSigningRootMintLockRecordName;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

/// Generation 1 of a root filed under the algorithm this build mints.
final rootSlot1 =
    '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1';

/// An [InMemoryAtKeysIo] that runs [beforeUpdate] once, immediately before the
/// nth [update] opens.
///
/// The mint's read-decide-write spans three awaits, and the sibling that can
/// invalidate its decision is the client's own PQ start, fired unawaited. There
/// is no way to make that interleaving happen on demand from outside, so the
/// hook stages it exactly: the private lands in the instant between the mint
/// deciding it holds nothing and the store opening for the write.
class _RacingAtKeysIo extends InMemoryAtKeysIo {
  _RacingAtKeysIo({required this.atUpdate, required this.beforeUpdate});

  final int atUpdate;
  final Future<void> Function(InMemoryAtKeysIo io) beforeUpdate;
  int _updates = 0;
  bool _fired = false;

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    _updates++;
    if (_updates == atUpdate && !_fired) {
      _fired = true;
      await beforeUpdate(this);
    }
    return super.update(atsign, mutate);
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The atSign's root of trust.
///
/// Every property here is about the same thing: two roots would leave half an
/// atSign's enrollments chaining to one the other half rejects, and D1 builds
/// no rotation able to reconcile that. The record itself is mutable — a
/// successor has to be advertised beside its retired predecessor — so what
/// keeps there being one root is `_rootlock@<atSign>` plus the reconciliation
/// that retires a private the record does not advertise.
void main() {
  const atSign = '@alice';

  setUpAll(() {
    registerFallbackValue(FakeUpdateVerbBuilder());
    registerFallbackValue(FakeAtKey());
  });

  /// [published] holds only the writes to the ROOT RECORD; [verbs] holds every
  /// verb in order, so a test can say what was taken before what was written.
  /// Separated because the mint now issues a lock take and a lock release
  /// around the publish, and a bare list would make `.single` mean something
  /// different in every test.
  ({
    MockAtClient client,
    List<UpdateVerbBuilder> published,
    List<VerbBuilder> verbs
  }) client(
      {bool lockHeldElsewhere = false,
      bool publishFails = false,
      String? enrollmentId = 'enrollment-1',
      Uint8List? publishedRoot,
      List<({Uint8List key, KeyEntryStatus status})>? publishedRoots,
      bool rootUnreadable = false}) {
    // One entry or several. `publishedRoots` is what a record mid-rotation
    // looks like — a successor active beside its retired predecessor — and
    // `publishedRoot` stays as the one-entry shorthand every other test uses.
    final entries = publishedRoots ??
        (publishedRoot == null
            ? null
            : [(key: publishedRoot, status: KeyEntryStatus.active)]);
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    // The signing-root pull reads the enrollment id off the lookup to tell an
    // APKAM enrollment from a client using the atSign's own keys.
    final lookup = MockAtLookUp();
    when(() => secondary.atLookUp).thenReturn(lookup);
    when(() => lookup.enrollmentId).thenReturn(enrollmentId);
    final published = <UpdateVerbBuilder>[];
    final verbs = <VerbBuilder>[];
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    // The published-record read: confirmed absent unless the fixture holds
    // one, unreadable when asked to be.
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
      if (rootUnreadable) {
        throw AtLookUpException('AT0011', 'the record cannot be read');
      }
      if (entries == null) {
        throw KeyNotFoundException('public:pq_signing_root$atSign not found');
      }
      return Future.value(AtValue()
        ..value = jsonEncode(apskAdvertisement(keys: [
          for (final entry in entries)
            ApskSigningKey.forPublicKey(
                alg: PqSigningRoot.rootKeyAlgo,
                pub: base64Encode(entry.key),
                status: entry.status)
        ])));
    });
    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      // Type-tested, never cast: the lock release is a DeleteVerbBuilder, and a
      // cast would throw inside the mock where MintLock's own catch swallows
      // it — a release that never happened, reported as one that did.
      final builder = inv.positionalArguments[0] as VerbBuilder;
      verbs.add(builder);
      if (builder is UpdateVerbBuilder) {
        if (builder.atKey.key == pqSigningRootMintLockRecordName) {
          if (lockHeldElsewhere) {
            // What the atServer says to the loser of the race.
            throw AtLookUpException(
                'AT0023', 'Immutable records may not be updated');
          }
          return 'data:1';
        }
        published.add(builder);
        if (publishFails) {
          throw AtLookUpException('AT0011', 'connection closed');
        }
      }
      return 'data:1';
    });
    return (client: atClient, published: published, verbs: verbs);
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
        .getAtSignKey(rootSlot1, CryptographicMaterialRole.privateSigning);
    expect(filed, isNotNull,
        reason: 'a published root whose private did not survive strands every '
            'enrollment on the atSign, and D1 builds no rotation to replace '
            'it with');
    expect(filed!.algorithm, CryptographicMaterialAlgorithm.mlDsa65);

    final record = c.published.single;
    expect(record.atKey.key, PqSigningRoot.recordName);
    expect(record.atKey.metadata.immutable, isFalse,
        reason: 'the record is an advertisement of signing keys, and a '
            'successor has to be added beside its retired predecessor — which '
            'an immutable record makes unimplementable. The interlock is '
            '_rootlock, asserted below');
    expect(record.atKey.metadata.isPublic, isTrue);
    expect(jsonDecode(record.value!)['keys'], hasLength(1));

    // The lock, in order: taken before anything is generated, and never
    // deleted.
    expect(c.verbs.first, isA<UpdateVerbBuilder>());
    expect((c.verbs.first as UpdateVerbBuilder).atKey.key,
        pqSigningRootMintLockRecordName,
        reason: 'the lock is what stops two privileged enrollments each '
            'finding no root and each minting one, so it has to be taken '
            'before the record is re-read, not after');
    expect(c.verbs.whereType<DeleteVerbBuilder>(), isEmpty,
        reason: 'the winner does not release the lock — the ttl does. It is an '
            'election token with a cooldown, not a mutex, and deleting it was '
            'how a holder finishing late removed its SUCCESSOR\'s lock: the '
            'delete forced past the immutable record without checking it still '
            'owned the one it was removing');
    expect(
        c.verbs
            .whereType<UpdateVerbBuilder>()
            .where((v) => v.atKey.key == pqSigningRootMintLockRecordName),
        hasLength(1),
        reason: 'and it is taken exactly once — a second take inside one mint '
            'would be refused by the atServer anyway');
  });

  test('the published record emits its exact wire shape — raw literals',
      () async {
    // Emitter pin (frozen forever): this is what a reader in the field parses,
    // and after the GA minor those readers exist. Raw strings deliberately —
    // the sibling tests assert through PqSigningRoot's own constants, which
    // follow a changed value.
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

  test('nothing can encapsulate to the root — its algorithm has no KEM',
      () async {
    // The reader-side half of "the root is a signing key; nothing encapsulates
    // to it, at onboarding or ever". The wire pin above asserts what the
    // WRITER says (`use: sign`), which a sender is free to ignore. This asserts
    // the sender CANNOT act on the record as a sealing target even handed it
    // directly: there is no KEM behind its algorithm, the algorithm is not
    // offered for key establishment, and the selector every sealing path uses
    // returns nothing for its entry.
    final c = client();

    await PqSigningRoot(c.client, keysIo: await keysIo())
        .mintIfAbsent(isFullyPrivileged: true);

    final body = jsonDecode(c.published.single.value!) as Map<String, dynamic>;
    final entries = (body['keys'] as List)
        .map(PackageKey.fromJson)
        .whereType<PackageKey>()
        .toList();
    expect(entries, hasLength(1),
        reason: 'the control: the root record parses as the same key-entry '
            'vocabulary a sealable advertisement uses, so the nulls below mean '
            '"cannot be sealed to" rather than "could not be read at all"');

    expect(SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing), isNotNull,
        reason: 'positive control for kemFor — the null below has to be about '
            'the root\'s algorithm and not about the lookup answering null '
            'for everything');
    expect(SecretSharingAlgos.kemFor(entries.single.alg), isNull,
        reason: 'the root advertises "${entries.single.alg}", and this build '
            'has no KEM for it: a sender handed the published root has '
            'nothing to encapsulate with, whatever the record claims');
    expect(SecretSharingAlgos.keyAlgos, isNot(contains(entries.single.alg)),
        reason: 'and it is not offered for key establishment, so no '
            'negotiation reaches it in the first place');

    final asIfSealable = KeyPackage(
        enrollmentId: 'E1', createdAt: DateTime.now().toUtc(), keys: entries);
    expect(asIfSealable.bestKeyFor([entries.single.alg]), isNull,
        reason: 'asked for the root\'s OWN algorithm — so the only thing '
            'making this null is that every sealing path asks for use=enc '
            'while the root says use=sign. Asking for keyAlgos here would '
            'pass for the wrong reason, since that list does not name the '
            'root algorithm either');
    expect(asIfSealable.suites, isEmpty,
        reason: 'and it claims no sealing construction, because a signing key '
            'opens none');
  });

  test('a copied keyfile signs with the root private on the second host',
      () async {
    // UC-A2.2: a second host running against a COPY of E1's keyfile is the
    // same enrollment, not a second one. Nothing anywhere copied a keyfile
    // that HOLDS the root private and then drove a second client from it, so
    // the clause rested on the copy being conveyed nothing — which is exactly
    // the case that has to work.
    final a = client();
    final ioA = await keysIo();
    // The flat enrollment id is what a copy carries to the atServer, and so
    // what makes the second host present as E1 rather than as a new
    // enrollment. It is why the namespace authorisations follow the copy. The
    // atsign is set for the same reason a real keyfile has one: typed material
    // will not serialize without it, and a copy is made of the serialized form.
    (await ioA.read(atSign))
      ..enrollmentId = 'enrollment-1'
      ..atsign = atSign.toAtsign();
    await PqSigningRoot(a.client, keysIo: ioA)
        .mintIfAbsent(isFullyPrivileged: true);

    final rootBody =
        jsonDecode(a.published.single.value!) as Map<String, dynamic>;
    final rootPublic = base64Decode(((rootBody['keys'] as List).single
        as Map<String, dynamic>)['pub'] as String);

    // The copy: through the JSON a .atKeys file holds, which is the whole of
    // what copying one does. Nothing is re-minted and nothing is conveyed.
    final ioB = InMemoryAtKeysIo();
    await ioB.write(
        atSign,
        AtKeys.fromJson(
            jsonDecode(jsonEncode((await ioA.read(atSign)).toJson()))
                as Map<String, dynamic>));

    final hostB = await PqSigningRoot(client(publishedRoot: rootPublic).client,
            keysIo: ioB)
        .signingKey(atSign);
    final hostA = await PqSigningRoot(a.client, keysIo: ioA).signingKey(atSign);

    expect(hostA, isNotNull, reason: 'the minting host holds its own root');
    expect(hostB, isNotNull,
        reason: 'and so does the copy, without being conveyed anything');
    expect(hostB!.private, hostA!.private,
        reason: 'the SAME private — one root, two hosts, one enrollment');
    expect(hostB.kid, hostA.kid,
        reason: 'naming the same advertised entry, so a link either host '
            'signs points at the same published key');

    // Resolving is not signing. This is the arm the row asked for: the copy
    // produces a signature the atSign's PUBLISHED root verifies, so a
    // verifier cannot tell the two hosts apart — which is what "share the
    // root" has to mean to be worth stating.
    final message = Uint8List.fromList(utf8.encode('a link signed on host B'));
    final signature = await MlDsa65PureDartAlgo()
        .signBytes(message, secretKey: hostB.private);
    expect(
        await MlDsa65PureDartAlgo()
            .verifyBytes(message, signature: signature, publicKey: rootPublic),
        isTrue,
        reason: 'host B signed with the copied private and the published root '
            'verifies it');
    expect(
        await MlDsa65PureDartAlgo().verifyBytes(
            Uint8List.fromList(utf8.encode('a different link')),
            signature: signature,
            publicKey: rootPublic),
        isFalse,
        reason: 'the control: the verify above is checking THIS message, not '
            'answering true for anything put in front of it');

    expect((await ioB.read(atSign)).enrollmentId, 'enrollment-1',
        reason: 'and the copy carries E1\'s enrollment id, which is what '
            'makes the second host present as E1 to the atServer and so pick '
            'up its namespace authorisations rather than a fresh grant');

    final fresh = InMemoryAtKeysIo();
    await fresh.write(atSign, AtKeys());
    expect(
        await PqSigningRoot(client(publishedRoot: rootPublic).client,
                keysIo: fresh)
            .signingKey(atSign),
        isNull,
        reason: 'the control: an UNCOPIED keyfile for the same atSign, reading '
            'the same published record, resolves nothing — so everything '
            'above is about the copy and not about the resolver answering for '
            'any keyfile');
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
    expect(c.verbs, isEmpty,
        reason: 'and it must not take the mint lock either — a lock taken '
            'before the privilege check would let a scoped enrollment block '
            'every privileged one on the atSign for the ttl, which is the '
            'inverse of what the lock is for');
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
        reason: 'a root whose private nobody holds cannot be replaced without '
            'a rotation, and D1 builds none — so publishing before the '
            'private is durable is not a retryable mistake');
  });

  test('losing the mint lock generates nothing and files nothing', () async {
    final c = client(lockHeldElsewhere: true);
    final io = await keysIo();
    final root = PqSigningRoot(c.client, keysIo: io);

    expect(await root.mintIfAbsent(isFullyPrivileged: true), isNull,
        reason: 'another of this atSign\'s enrollments is minting; this one '
            'waits to be given the root rather than treating it as a failure');

    expect(c.published, isEmpty,
        reason: 'and it must not have written the record. With the record '
            'mutable, a loser that published anyway would OVERWRITE the '
            'winner\'s root rather than be refused by the atServer');
    expect((await io.read(atSign)).keys, isEmpty,
        reason: 'nothing was generated either. This is what the lock buys '
            'over a refused create: the loser never mints a keypair, so '
            'there is no losing pair to retire and no window in which it '
            'reads as holding the root');

    // The heal that never having filed anything leaves open: with nothing
    // active held, the pull asks the namespace.
    final broadcast = _RecordingSharing();
    final asked = await root.requestPrivateIfAbsent(
      isFullyPrivileged: () async => true,
      sharing: broadcast,
      namespace: 'buzz',
    );
    expect(asked, greaterThan(0),
        reason: 'a loser that read as holding the root would never ask, and '
            'nothing else repairs it — D1 builds no rotation that could mint '
            'a replacement');
  });

  test('a root published while the lock was being taken is not overwritten',
      () async {
    // The window the lock alone does not close: the absence check runs BEFORE
    // the lock, so a winner that published in between is invisible to it. With
    // an immutable record the atServer refused the second write; with a
    // mutable one, nothing but the re-read under the lock stops this mint
    // overwriting the root it thought was missing.
    final winner = await MlDsa65PureDartAlgo().generateKeyPair();
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookup = MockAtLookUp();
    when(() => secondary.atLookUp).thenReturn(lookup);
    when(() => lookup.enrollmentId).thenReturn('enrollment-1');
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    final verbs = <VerbBuilder>[];
    var reads = 0;
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
      reads++;
      // Absent to the check outside the lock; published by the time the mint
      // re-reads under it.
      if (reads == 1) throw KeyNotFoundException('not found');
      return Future.value(AtValue()
        ..value = jsonEncode(apskAdvertisement(keys: [
          ApskSigningKey.forPublicKey(
              alg: PqSigningRoot.rootKeyAlgo,
              pub: base64Encode(winner.publicKey))
        ])));
    });
    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      verbs.add(inv.positionalArguments[0] as VerbBuilder);
      return 'data:1';
    });

    final io = await keysIo();
    final minted = await PqSigningRoot(atClient, keysIo: io)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(minted, isNull);
    expect(reads, greaterThan(1),
        reason: 'the record must be read a SECOND time under the lock, or '
            'this test proves nothing about the window it exists to close');
    final rootWrites = verbs
        .whereType<UpdateVerbBuilder>()
        .where((b) => b.atKey.key == PqSigningRoot.recordName);
    expect(rootWrites, isEmpty,
        reason: 'the winner\'s root stands. This is the one outcome the '
            'interlock exists to prevent, and dropping `immutable` is what '
            'made it possible at all');
    expect((await io.read(atSign)).keys, isEmpty,
        reason: 'and the re-read happens before the keygen, so nothing was '
            'generated either');
  });

  group('when the publish call fails but its outcome is unknown', () {
    // A failed write and a write that LANDED and was not reported throw the
    // same way, and they need opposite handling. Getting the second one wrong
    // is the expensive mistake: retiring the pair for a root this client did
    // publish leaves every enrollment on the atSign chaining to a key nobody
    // holds, and D1 builds no rotation to replace it with.
    //
    // "The atServer refused a second create" is no longer one of the cases —
    // the record is mutable and the write goes out under the lock — so the
    // third case is the one the lock cannot exclude: a peer published anyway.

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
        final builder = inv.positionalArguments[0] as VerbBuilder;
        // The lock is taken and released normally; only the record write is
        // the one whose outcome is unknown.
        if (builder is! UpdateVerbBuilder ||
            builder.atKey.key == pqSigningRootMintLockRecordName) {
          return 'data:1';
        }
        publishedValue = builder.value;
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
          reason: 'and the private must survive: nothing re-mints a published '
              'root, so retiring it would leave the atSign advertising a key '
              'no enrollment holds');
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
        // Two absence checks now — one outside the mint lock and one under it
        // — and both must answer "no root". It is the reconciliation read
        // after the failed publish that cannot be served.
        if (reads <= 2) throw KeyNotFoundException('not found');
        throw AtLookUpException('AT0011', 'cannot read');
      });
      when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer((inv) async {
        final builder = inv.positionalArguments[0] as VerbBuilder;
        if (builder is! UpdateVerbBuilder ||
            builder.atKey.key == pqSigningRootMintLockRecordName) {
          return 'data:1';
        }
        throw AtLookUpException('AT0011', 'connection closed');
      });

      final io = await keysIo();
      final root = PqSigningRoot(atClient, keysIo: io);

      expect(await root.mintIfAbsent(isFullyPrivileged: true), isNull,
          reason: 'it cannot claim to have minted what it cannot confirm');
      expect(await root.privateHalf(atSign), isNotNull,
          reason: 'but it must NOT retire on an unknown outcome: a later '
              'start reconciles the held pair against the record, and '
              'retiring a private whose record landed cannot be undone');
    });

    test('a write that failed with nothing published retires the pair',
        () async {
      // ⚠️ The branch the mutable record TEMPTS you to change, and must not.
      // "There is no one chance to burn any more, so keep the pair and let a
      // later start republish it" is true about the record and false about
      // this codebase: nothing on a start path mints. `mintIfAbsent` runs at
      // activation and at retrofit only — `pq_client_bootstrap.dart` says so
      // in as many words, "a mint is once per keyfile while a start is every
      // time" — so a kept pair is permanent, blocks the pull that is the one
      // heal that DOES run every start, and gets a root link signed with it
      // that nothing ever rewrites.
      final c = client(publishFails: true);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      expect(await root.mintIfAbsent(isFullyPrivileged: true), isNull,
          reason: 'nothing was published, so nothing is claimed');
      expect(await root.privateHalf(atSign), isNull,
          reason: 'the pair is retired, so this enrollment stops reading as a '
              'holder of the root');
      final materials = (await io.read(atSign)).keys;
      expect(materials, isNotEmpty,
          reason: 'key material is never removed, only retired — the bytes '
              'stay in the file, marked dead');
      expect(materials.map((m) => m.status).toSet(),
          {CryptographicMaterialStatus.dead});

      // The heal the retirement re-opens, and the reason it has to be re-opened
      // here rather than at a later mint: this is the only one that runs again.
      final asked = await root.requestPrivateIfAbsent(
        isFullyPrivileged: () async => true,
        sharing: _RecordingSharing(),
        namespace: 'buzz',
      );
      expect(asked, greaterThan(0));
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
    expect(c.published, isEmpty);
    expect(c.verbs, isEmpty,
        reason: 'the cheap read settles it, so the ordinary case — an atSign '
            'that already has a root — costs no remote WRITE at all. Taking '
            'the lock first would put one on every activation and every '
            'retrofit, for nothing');
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
        reason: 'absent and unreadable are different answers, and a client '
            'that cannot tell them apart would overwrite the root it failed '
            'to read');
    expect(c.published, isEmpty);
    expect(c.verbs, isEmpty,
        reason: 'and it aborts BEFORE taking the lock, so a run of unreadable '
            'records cannot leave the atSign locked out of minting');
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
    keys.addKey(CryptographicMaterial(
      keyId: rootSlot1,
      role: CryptographicMaterialRole.privateSigning,
      algorithm: CryptographicMaterialAlgorithm.mlDsa65,
      bytes: AtBytes(held.secretKey),
      createdAt: createdAt,
    ));
    keys.addKey(CryptographicMaterial(
      keyId: rootSlot1,
      role: CryptographicMaterialRole.publicVerification,
      algorithm: CryptographicMaterialAlgorithm.mlDsa65,
      bytes: AtBytes(held.publicKey),
      createdAt: createdAt,
    ));
    await freshIo.flush(atSign.toAtsign(), keys);

    final republished = await PqSigningRoot(c.client, keysIo: freshIo)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(republished, held.publicKey,
        reason: 'minting a fresh pair here would publish a public whose '
            'private was discarded, leaving a root nobody holds the key to. '
            'The held pair is the only safe thing to publish');
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

  test('a private arriving mid-mint is kept, and the minted pair discarded',
      () async {
    // The mint decides it holds nothing, then awaits three times — the record
    // fetch, a retire, and an ML-DSA keygen — before it writes. The client's
    // own PQ start runs unawaited beside it and files whatever a peer conveyed
    // in that window, so the decision is taken against a snapshot that is
    // already stale by the time it is acted on.
    //
    // Nothing below refuses the second key either: at_auth's
    // single-active-per-algorithm rule is enrollment-scoped, and root material
    // is atSign-scope with a null enrollment id. Two active root privates were
    // therefore writable AND survived a keyfile round trip, with `.firstOrNull`
    // returning the EARLIEST filed — the losing pair, not the conveyed key
    // every other enrollment can verify against.
    final arrived = await MlDsa65PureDartAlgo().generateKeyPair();
    final c = client();
    final io = _RacingAtKeysIo(
      // The mint's first update is _storeFreshPair's own: the record is absent,
      // so the poison heal and the orphan retire above it never run.
      atUpdate: 1,
      beforeUpdate: (io) async {
        final keys = await io.read(atSign);
        keys.addKey(CryptographicMaterial(
          keyId: rootSlot1,
          role: CryptographicMaterialRole.privateSigning,
          algorithm: PqSigningRoot.rootKeyAlgoToken,
          bytes: AtBytes(arrived.secretKey),
          createdAt: DateTime.now().toUtc(),
        ));
        await io.flush(atSign.toAtsign(), keys);
      },
    );
    await io.write(atSign, AtKeys());

    final minted = await PqSigningRoot(c.client, keysIo: io)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(minted, isNull,
        reason: 'the mint is abandoned rather than completed: the private that '
            'arrived is the one a peer conveyed, and publishing over it would '
            'strand every enrollment that already has it');
    expect(c.published, isEmpty,
        reason: 'nothing is published for a pair that was never filed');
    final keys = await io.read(atSign);
    final actives = keys.atSignKeys.where((m) =>
        m.role == CryptographicMaterialRole.privateSigning &&
        m.status == CryptographicMaterialStatus.active);
    expect(actives, hasLength(1),
        reason: 'two active root privates make "what do I sign with" a '
            'question answered by insertion order');
    expect(actives.single.bytes.bytes, arrived.secretKey);
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
    // `CryptographicMaterialAlgorithm.known` exists for warn-level tooling and explicitly
    // does not gate what may be filed, so a reader that recognised only known
    // tokens would be a second, undocumented gate.
    const laterAlgo =
        CryptographicMaterialAlgorithm.of('some-later-signing-algo');
    final c = client();
    final io = await keysIo();
    final keys = await io.read(atSign);
    final held = Uint8List.fromList([7, 8, 9]);
    keys.addKey(CryptographicMaterial(
      keyId: '${PqSigningRoot.keyIdPrefixFor(laterAlgo)}1',
      role: CryptographicMaterialRole.privateSigning,
      algorithm: laterAlgo,
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
    keys.addKey(CryptographicMaterial(
      keyId: '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1',
      role: CryptographicMaterialRole.privateSigning,
      algorithm: PqSigningRoot.rootKeyAlgoToken,
      bytes: AtBytes(Uint8List.fromList([1])),
      createdAt: DateTime.now().toUtc(),
    ));

    expect(
        keys.nextAtSignGeneration(
            PqSigningRoot.keyIdRole, PqSigningRoot.rootKeyAlgoToken),
        2);
    expect(
        keys.nextAtSignGeneration(PqSigningRoot.keyIdRole,
            CryptographicMaterialAlgorithm.of('another-algo')),
        1);
  });

  group('a record advertising a successor beside a retired predecessor', () {
    // The state a rotation passes through, staged directly: the record carries
    // both entries, and this client still holds the predecessor's private.
    // Every path below asks the same question — "is the private I am looking
    // at the root's?" — and D1's claim is that the answer is about the SET the
    // record advertises, not about its one active entry.
    late ({Uint8List publicKey, Uint8List secretKey}) predecessor;
    late ({Uint8List publicKey, Uint8List secretKey}) successor;

    setUp(() async {
      predecessor = await MlDsa65PureDartAlgo().generateKeyPair();
      successor = await MlDsa65PureDartAlgo().generateKeyPair();
    });

    ({
      MockAtClient client,
      List<UpdateVerbBuilder> published,
      List<VerbBuilder> verbs
    }) rotating() => client(publishedRoots: [
          (key: successor.publicKey, status: KeyEntryStatus.active),
          (key: predecessor.publicKey, status: KeyEntryStatus.retired),
        ]);

    test('both entries are read back, active first', () async {
      final c = rotating();

      final all = await PqSigningRoot.publishedPublicKeys(c.client, atSign);
      expect(all, [successor.publicKey, predecessor.publicKey]);
      expect(await PqSigningRoot.publishedPublicKey(c.client, atSign),
          successor.publicKey,
          reason: 'the singular one means the ACTIVE root, which is what a '
              'signer and a correspondence check want');
    });

    test('a held predecessor private is not treated as poison', () async {
      final c = rotating();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, predecessor.secretKey), isTrue);

      final retired = await root.reconcileHeldPrivate(atSign);

      expect(retired, isFalse,
          reason: 'the predecessor is advertised — retired, but advertised. '
              'Retiring it locally as if it corresponded to nothing published '
              'is the heal for a poisoned keyfile, and this keyfile is not '
              'poisoned');
      expect(await root.privateHalf(atSign), predecessor.secretKey);
    });

    test('a successor conveyed to a holder of the predecessor is filed',
        () async {
      final c = rotating();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, predecessor.secretKey), isTrue);

      final filed = await root.file(
          atSign,
          Secret(
            namespace: 'ns',
            name: PqSigningRoot.secretName,
            value: base64Encode(successor.secretKey),
          ));

      expect(filed, isTrue,
          reason: 'a client already holding the predecessor is exactly the '
              'client a rotation has to reach; refusing the successor here '
              'leaves it signing with a key that is no longer active');
      expect(await root.privateHalf(atSign), successor.secretKey,
          reason: 'the active private is the successor once it is filed');
      final keys = await io.read(atSign);
      final predecessorSlot = keys.atSignKeys.firstWhere((m) =>
          m.role == CryptographicMaterialRole.privateSigning &&
          _bytesEqual(m.bytes.bytes, predecessor.secretKey));
      expect(predecessorSlot.status, CryptographicMaterialStatus.retired,
          reason: 'the predecessor keeps its slot and its bytes — they are '
              'still what verifies what it signed — but stops being active, '
              'so exactly one private answers "what do I sign with"');
    });

    test('a late predecessor never displaces the held successor', () async {
      // The supersede has a direction, and the record decides it — not which
      // private arrived last. A holder that has not yet healed can convey the
      // predecessor to a client already holding the successor, and the answer
      // is to keep what is active.
      //
      // It is *recognised* rather than discarded as poison — the record
      // advertises it — but it is not filed beside the successor: a retired
      // key's private signs nothing, so a second slot for it would be dead
      // material that every later reader has to reason about.
      final c = rotating();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, successor.secretKey), isTrue);
      final before = (await io.read(atSign)).atSignKeys.length;

      final filed = await root.file(
          atSign,
          Secret(
            namespace: 'ns',
            name: PqSigningRoot.secretName,
            value: base64Encode(predecessor.secretKey),
          ));

      expect(filed, isFalse);
      expect(await root.privateHalf(atSign), successor.secretKey);
      expect((await io.read(atSign)).atSignKeys.length, before,
          reason: 'no slot is spent on a private that can sign nothing');
    });

    test('a poisoned leftover does not survive the real key arriving',
        () async {
      // A private corresponding to no advertised entry is the leftover of a
      // lost create. Filing the real key beside it and leaving it active would
      // let it go on winning "what do I sign with" — the arriving key would be
      // held and still not used, which is the worst of both.
      final c = rotating();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      final poison = await MlDsa65PureDartAlgo().generateKeyPair();
      expect(await root.store(atSign, poison.secretKey), isTrue);

      final filed = await root.file(
          atSign,
          Secret(
            namespace: 'ns',
            name: PqSigningRoot.secretName,
            value: base64Encode(successor.secretKey),
          ));

      expect(filed, isTrue);
      expect(await root.privateHalf(atSign), successor.secretKey,
          reason: 'the leftover is retired as the real key is filed, so the '
              'active private is the one the record calls active');
    });

    test('a retired-only private is refused even by an empty keyfile',
        () async {
      // The gap the "not filed beside an active one" rule left: with nothing
      // active to sit beside, `store`'s guard does not fire and `CryptographicMaterial`
      // defaults to active — so the predecessor became the keyfile's sole
      // ACTIVE private, and the single-private short circuit then hands it back
      // without ever reading the record. The client would sign root links with
      // a key the record calls retired.
      //
      // Production-shaped: a holder that has not yet healed conveys the only
      // private it has to a freshly approved privileged enrollment.
      final c = rotating();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);

      final filed = await root.file(
          atSign,
          Secret(
            namespace: 'ns',
            name: PqSigningRoot.secretName,
            value: base64Encode(predecessor.secretKey),
          ));

      expect(filed, isFalse,
          reason: 'a retired key signs nothing, whether or not something '
              'active is already held');
      expect(await root.privateHalf(atSign), isNull);
      expect((await io.read(atSign)).atSignKeys, isEmpty,
          reason: 'no slot is spent on it, so the pull asks again and a '
              'holder with the successor can heal this client');
    });

    test('storing a private already held reports success and adds no slot',
        () async {
      final c = rotating();
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, successor.secretKey), isTrue);
      final before = (await io.read(atSign)).atSignKeys.length;

      expect(await root.store(atSign, successor.secretKey), isTrue,
          reason: 'the question store answers is "is THIS private held", and '
              'it is');
      expect((await io.read(atSign)).atSignKeys.length, before,
          reason: 'filing the same bytes under a second slot would leave two '
              'actives no reader could tell apart');
    });
  });

  group('choosing between two active root privates', () {
    // Two actives are writable and survive a keyfile round trip: at_auth's
    // single-active-per-algorithm rule is enrollment-scoped, and root material
    // is atSign-scope. Filed directly here, because the mint no longer produces
    // the state and staging it through the API would prove only that.
    late ({Uint8List publicKey, Uint8List secretKey}) first;
    late ({Uint8List publicKey, Uint8List secretKey}) second;

    setUp(() async {
      first = await MlDsa65PureDartAlgo().generateKeyPair();
      second = await MlDsa65PureDartAlgo().generateKeyPair();
    });

    Future<InMemoryAtKeysIo> keysHolding(
        List<({Uint8List publicKey, Uint8List secretKey})> pairs) async {
      final io = await keysIo();
      final keys = await io.read(atSign);
      for (var i = 0; i < pairs.length; i++) {
        keys.addKey(CryptographicMaterial(
          keyId:
              '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}${i + 1}',
          role: CryptographicMaterialRole.privateSigning,
          algorithm: PqSigningRoot.rootKeyAlgoToken,
          bytes: AtBytes(pairs[i].secretKey),
          createdAt: DateTime.now().toUtc(),
        ));
      }
      await io.flush(atSign.toAtsign(), keys);
      return io;
    }

    test('the record decides, not the order the keyfile filed them', () async {
      // `first` is filed first, so anything taking the head of the keyfile
      // returns it. The record says the OTHER one is active.
      final c = client(publishedRoots: [
        (key: second.publicKey, status: KeyEntryStatus.active),
        (key: first.publicKey, status: KeyEntryStatus.retired),
      ]);
      final io = await keysHolding([first, second]);

      expect(await PqSigningRoot(c.client, keysIo: io).privateHalf(atSign),
          second.secretKey,
          reason: 'the private that may sign is the one the record calls '
              'active; filed order is not evidence of anything');
    });

    test('a single held private is answered without reading the record',
        () async {
      // The property four production call sites document as the reason they
      // check possession BEFORE paying for a round trip — one of them on the
      // approval path. A selector that consults the record unconditionally
      // would break all four silently, since they would still be correct, just
      // no longer cheap.
      final c = client(publishedRoots: [
        (key: first.publicKey, status: KeyEntryStatus.active),
      ]);
      final io = await keysHolding([first]);

      expect(await PqSigningRoot(c.client, keysIo: io).privateHalf(atSign),
          first.secretKey);
      verifyNever(() => c.client
          .get(any(), getRequestOptions: any(named: 'getRequestOptions')));
    });

    test('an unreadable record leaves the first filed as the answer', () async {
      final c = client(rootUnreadable: true);
      final io = await keysHolding([first, second]);

      expect(await PqSigningRoot(c.client, keysIo: io).privateHalf(atSign),
          first.secretKey,
          reason: 'an unreadable record is no evidence. A client that stopped '
              'anchoring and started broadcasting for a key it already held '
              'every time the atServer hiccupped is the worse failure');
    });

    test('none corresponding to an active entry signs nothing', () async {
      final c = client(publishedRoots: [
        (key: first.publicKey, status: KeyEntryStatus.retired),
        (key: second.publicKey, status: KeyEntryStatus.retired),
      ]);
      final io = await keysHolding([first, second]);

      expect(
          await PqSigningRoot(c.client, keysIo: io).privateHalf(atSign), isNull,
          reason: 'both are advertised, so neither is poison — but a retired '
              'key signs nothing, and answering with one would publish an '
              'anchor every verifier rejects');
    });

    test('every unadvertised private is retired, not just the first', () async {
      // The heal used to judge one private chosen by filed order, so a second
      // unadvertised one stayed active and went on answering "do I hold the
      // root" with bytes no verifier accepts — the state the heal exists to
      // clear, surviving the heal.
      final real = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoots: [
        (key: real.publicKey, status: KeyEntryStatus.active),
      ]);
      final io = await keysHolding([first, second]);

      final retired = await PqSigningRoot(c.client, keysIo: io)
          .reconcileHeldPrivate(atSign);

      expect(retired, isTrue);
      final actives = (await io.read(atSign)).atSignKeys.where((m) =>
          m.role == CryptographicMaterialRole.privateSigning &&
          m.status == CryptographicMaterialStatus.active);
      expect(actives, isEmpty,
          reason: 'both correspond to nothing advertised, so both go');
    });
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

    test('a private matching only a RETIRED entry is left alone', () async {
      // The control arm for the row below, and the doctrine this heal was
      // built on: a predecessor the record still vouches for is not a
      // poisoned leftover. Without this arm the row below would pass on a
      // heal that simply retired everything not active.
      final successor = await MlDsa65PureDartAlgo().generateKeyPair();
      final predecessor = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoots: [
        (key: successor.publicKey, status: KeyEntryStatus.active),
        (key: predecessor.publicKey, status: KeyEntryStatus.retired),
      ]);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, predecessor.secretKey), isTrue);

      expect(await root.reconcileHeldPrivate(atSign), isFalse);
      expect(await root.privateHalf(atSign), predecessor.secretKey,
          reason: 'retirement withdraws the future and keeps the past, so the '
              'record still vouches for this key and it is not a leftover');
    });

    test('a private matching only a status this build cannot read is retired',
        () async {
      // The differential against the arm above, and the reason this heal has
      // to make the SAME judgement the verifier makes. `PqSigningChain` will
      // not check a signature against an entry whose status it cannot read, so
      // a client that went on holding the matching private as active would
      // anchor links its own verifier then rejects — and the heal that clears
      // that state is this one. Until 2026-08-22 an unreadable status read as
      // `retired`, so this row and the one above were indistinguishable.
      final successor = await MlDsa65PureDartAlgo().generateKeyPair();
      final disowned = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = client(publishedRoots: [
        (key: successor.publicKey, status: KeyEntryStatus.active),
        (key: disowned.publicKey, status: KeyEntryStatus.of('revoked')),
      ]);
      final io = await keysIo();
      final root = PqSigningRoot(c.client, keysIo: io);
      expect(await root.store(atSign, disowned.secretKey), isTrue);

      expect(await root.reconcileHeldPrivate(atSign), isTrue);
      expect(await root.privateHalf(atSign), isNull,
          reason: 'the record says something about this key that this build '
              'cannot read, so it does not vouch for it - and while the '
              'private stays active the pull never asks a holder for the one '
              'the record does vouch for');
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
          reason: 'nothing re-mints a published root, so filing the wrong '
              'bytes sticks until a holder answers the pull — and a 32-byte '
              'buffer cannot sign anything the published root verifies');
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
