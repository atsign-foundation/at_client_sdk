import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/atsign.dart' show Atsign;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyAdvertisement, NskeySeed;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:test/test.dart';

/// Moving an arriving nskey private out of the transit buffer and into AtKeys.
///
/// The distinction being enforced is between material that can be recovered
/// and material that cannot. A content key is a cache — a reader re-fetches it
/// from its conveyance record. An nskey private is not: lose it and every
/// conveyance record sealed to it is unopenable, taking every value those
/// content keys protect with it. So it belongs where the never-lose contract
/// is, not in a store an app might persist however it likes.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  final privateBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

  Future<(InMemoryAtKeysIo, NskeyPrivateFiling)> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return (io, NskeyPrivateFiling(keysIo: io, atSign: atSign));
  }

  Secret nskeySecret(String kid, {String? ns}) => Secret(
        namespace: ns ?? namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
        value: base64Encode(privateBytes),
      );

  test('an arriving private is filed into AtKeys, keyed by namespace and kid',
      () async {
    final (io, filer) = await filing();

    expect(await filer.file(nskeySecret('kid-one')), isTrue);

    final keys = await io.read(atSign);
    final material = keys.getAtSignKey(
        NskeyPrivateFiling.keyIdFor(namespace, 'kid-one'),
        CryptographicKeyType.privateDecapsulation);
    expect(material, isNotNull,
        reason: 'this is the only copy that survives a restart — the transit '
            'store is in-memory by design');
    expect(material!.bytes.bytes, privateBytes);
    expect(material.keyAlgorithmType, KeyAlgorithmType.xWing);
  });

  test('the same kid in two namespaces files as two keys', () async {
    final (io, filer) = await filing();

    await filer.file(nskeySecret('shared-kid'));
    await filer.file(nskeySecret('shared-kid', ns: 'other'));

    final keys = await io.read(atSign);
    expect(
        keys.getAtSignKey(NskeyPrivateFiling.keyIdFor(namespace, 'shared-kid'),
            CryptographicKeyType.privateDecapsulation),
        isNotNull);
    expect(
        keys.getAtSignKey(NskeyPrivateFiling.keyIdFor('other', 'shared-kid'),
            CryptographicKeyType.privateDecapsulation),
        isNotNull,
        reason: 'kids are truncated hashes and are not unique across '
            'namespaces, so keying on the kid alone would let one namespace '
            'private silently displace another');
  });

  test('a re-delivered private is not filed twice', () async {
    final (_, filer) = await filing();

    expect(await filer.file(nskeySecret('kid-one')), isTrue);
    expect(await filer.file(nskeySecret('kid-one')), isFalse,
        reason: 'the substrate converges by re-sending, so arrival has to be '
            'idempotent — AtKeys.addKey rejects a duplicate outright');
  });

  test('a private with no kid in its name is refused', () async {
    final (io, filer) = await filing();

    expect(
        await filer.file(Secret(
            namespace: namespace,
            name: NskeyPrivateFiling.secretNamePrefix,
            value: base64Encode(privateBytes))),
        isFalse,
        reason: 'without a kid there is no way to tell which generation it '
            'opens, and filing it under a guess would be worse than refusing');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test('a private that does not derive the published public half is refused',
      () async {
    final real = await XWingKeyPair.generate();
    final other = await XWingKeyPair.generate();
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final filer = NskeyPrivateFiling(
      keysIo: io,
      atSign: atSign,
      publishedGeneration: (_, __) async => NskeyAdvertisement.single(
        publicKey: real.publicKeyBytes,
        alg: SecretSharingAlgos.xWing,
        suites: SecretSharingAlgos.openableSuitesFor(SecretSharingAlgos.xWing),
      ),
    );

    // Genuinely signed by this atSign, and genuinely an nskey private — just
    // not the one peers are sealing to. Only correspondence catches that.
    expect(
        await filer.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}kid-x',
            value: base64Encode(other.privateKeyBytes))),
        isFalse,
        reason: 'filing it would leave this client believing it can open a '
            'namespace it cannot, and the failure would surface later on data '
            'as corruption rather than as a bad key');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test('the matching private is accepted', () async {
    final real = await XWingKeyPair.generate();
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final filer = NskeyPrivateFiling(
      keysIo: io,
      atSign: atSign,
      publishedGeneration: (_, __) async => NskeyAdvertisement.single(
        publicKey: real.publicKeyBytes,
        alg: SecretSharingAlgos.xWing,
        suites: SecretSharingAlgos.openableSuitesFor(SecretSharingAlgos.xWing),
      ),
    );

    expect(
        await filer.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}kid-x',
            value: base64Encode(real.privateKeyBytes))),
        isTrue,
        reason: 'an X-Wing secret key is its seed, so the public half derives '
            'from it exactly — the check is precise, not heuristic');
  });

  test('only nskey privates are filed; other secrets pass through', () async {
    final (io, filer) = await filing();

    expect(
        await filer.filePending([
          Secret(namespace: namespace, name: 'an-app-token', value: 'v'),
          nskeySecret('kid-two'),
        ]),
        1);

    final keys = await io.read(atSign);
    expect(keys.keys, hasLength(1),
        reason: 'the substrate carries opaque secrets and this only claims its '
            'own — an app secret is none of the crypto layer\'s business');
    expect(
        keys.getAtSignKey(NskeyPrivateFiling.keyIdFor(namespace, 'kid-two'),
            CryptographicKeyType.privateDecapsulation),
        isNotNull);
  });

  test('every conveyed generation is filed, not just the newest', () async {
    final (io, filer) = await filing();

    expect(
        await filer
            .filePending([nskeySecret('gen-one'), nskeySecret('gen-two')]),
        2,
        reason: 'data written under a superseded key is still readable, and '
            'only its own private opens it — a client given the current '
            'generation alone could read nothing written before the last '
            'rotation');
    expect(await filer.readAllFor(namespace), hasLength(2));
  });

  test('re-draining the same store files nothing twice', () async {
    final (_, filer) = await filing();
    final held = [nskeySecret('kid-three')];

    expect(await filer.filePending(held), 1);
    expect(await filer.filePending(held), 0,
        reason: 'the substrate converges by re-sending, so the same secret is '
            'drained at every start; filing is idempotent on the keyfile');
  });

  test('what is stored is the seed; read() expands, readSeed() does not',
      () async {
    // ML-KEM is the arm where the two forms actually differ — X-Wing's seed
    // and secretKey are the same bytes, which is the accident that let a
    // conveyed decapsulation key pass for a seed until it reached ML-KEM.
    final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
    final seed = NskeySeed(kem.newSeed());
    final pair = await kem.keyPairFromSeed(seed.bytes);
    final (_, filer) = await filing();
    await filer.store(
        namespace: namespace,
        nskeyKid: 'kid-mlkem',
        seed: seed,
        keyAlgo: SecretSharingAlgos.mlKem1024);

    final readBack = await filer.readSeed(namespace, 'kid-mlkem');
    expect(readBack!.bytes, seed.bytes,
        reason: 'readSeed is the conveyable durable form, byte-identical to '
            'what was stored');

    final expanded = await filer.read(namespace, 'kid-mlkem');
    expect(expanded!.bytes, pair.secretKey,
        reason: 'read() answers with the expanded decapsulation key, ready '
            'for pqOpen');
    expect(expanded.bytes, isNot(seed.bytes),
        reason: 'under ML-KEM the two forms differ — the distinction the '
            'NskeySeed/NskeyDecapsulationKey types exist to keep');
  });

  group('a key source that cannot be read is not an empty one', () {
    // The three cases the readers have to keep apart. Two of them are ordinary
    // and answer "holds nothing"; the third means the material may be present
    // and unreadable, and answering "holds nothing" for it is what made a
    // corrupt keyfile indistinguishable from a cold start — which, since the
    // notification park landed, presents as a message held for a filing that
    // can never arrive.

    test('a source holding nothing yet reads as a genuine absence', () async {
      // Case 1: nothing written for this atSign. InMemoryAtKeysIo throws
      // AtKeysNotInMemoryException, which is an AtKeysSourceAbsentException.
      final filing =
          NskeyPrivateFiling(keysIo: InMemoryAtKeysIo(), atSign: atSign);

      expect(await filing.read(namespace, 'kid1'), isNull);
      expect(await filing.readSeed(namespace, 'kid1'), isNull);
      expect(await filing.readAll(), isEmpty);
      expect(await filing.readAllFor(namespace), isEmpty);
    });

    test('a readable source missing that entry also reads as absence',
        () async {
      // Case 2: the source reads fine and simply has no such key. Same answer,
      // and it must stay the same answer — this is the ordinary miss the
      // self-heal is built on.
      final io = InMemoryAtKeysIo();
      await io.write(atSign, AtKeys());
      final filing = NskeyPrivateFiling(keysIo: io, atSign: atSign);

      expect(await filing.read(namespace, 'kid1'), isNull);
      expect(await filing.readSeed(namespace, 'kid1'), isNull);
      expect(await filing.readAll(), isEmpty);
      expect(await filing.readAllFor(namespace), isEmpty);
    });

    test('an unreadable source is raised, not reported as absence', () async {
      // Case 3, and the whole point. read/readSeed/readAllFor raise so the
      // caller cannot mistake it for "holds nothing".
      final filing =
          NskeyPrivateFiling(keysIo: _UnreadableKeysIo(), atSign: atSign);

      await expectLater(filing.read(namespace, 'kid1'),
          throwsA(isA<AtKeysParseException>()));
      await expectLater(filing.readSeed(namespace, 'kid1'),
          throwsA(isA<AtKeysParseException>()));
      await expectLater(filing.readAllFor(namespace),
          throwsA(isA<AtKeysParseException>()));
    });

    test('readAll alone tolerates it, because a client is built through it',
        () async {
      // The deliberate exception: readAll's caller runs during client
      // construction, and a client that cannot be built at all is worse than
      // one that starts holding nothing. The failure is on the record at
      // `severe` from the shared reader rather than swallowed at `finer`.
      final filing =
          NskeyPrivateFiling(keysIo: _UnreadableKeysIo(), atSign: atSign);

      expect(await filing.readAll(), isEmpty);
    });
  });
}

/// A key source that exists and cannot be parsed — the case that used to be
/// indistinguishable from holding nothing.
///
/// `AtKeysParseException` deliberately, not `AtKeysSourceAbsentException`:
/// the point of the split is that only the latter means absence.
class _UnreadableKeysIo extends WrittenAtKeysIo {
  @override
  Future<AtKeys> read(String atsign) async =>
      throw AtKeysParseException('the keyfile for $atsign is not JSON');

  @override
  Future<void> write(String atsign, AtKeys atKeys) async {}

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) async {}

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {}
}
