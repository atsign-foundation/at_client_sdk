/// An install that never shipped one of the post-quantum key-establishment
/// algorithms, reading a record a sibling of the same atSign wrote under it.
///
/// Two enrollments of `@alice` share a namespace and its key material. The
/// namespace advertises **both** X-Wing and ML-KEM-1024 and both privates are
/// filed, so what an install can *receive* has already been widened on this
/// atSign. What separates the two installs is the code each is built from: the
/// writer here has moved what it *sends*, sealing content keys to ML-KEM-1024
/// and to nothing else, while the sibling is a build that registers only the
/// X-Wing conveyance provider. Its inability is real rather than configured —
/// there is no `at/nskey/MLKEM1024/AES/GCM` provider on it to route to,
/// whatever key material it holds — and giving it every private the writer
/// holds is what makes the missing provider the only available explanation for
/// the refusal.
///
/// That asymmetry is the point, and it is why the two moves have to happen in
/// that order on every install. Widening what an atSign can receive strands
/// nobody, because a writer still sealing to the older algorithm goes on
/// producing records the older build opens. Moving what a writer sends is what
/// strands a sibling that has not caught up, and nothing in the SDK removes
/// that. The refusal below is the ladder working rather than a defect, which
/// is why it is pinned here.
///
/// Both reading arms drive `AtClient.get`, the call an application makes,
/// against a remote secondary serving the records the writer produced. The
/// writer is driven through `CryptoRuntime` — the sequence every encrypting
/// write runs — so the conveyance record and the value are the ones production
/// composes, including which conveyance provider the send posture selects,
/// which is the whole subject.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/pipeline_backed_client.dart';

void main() {
  const alice = '@alice';
  const namespace = 'wavi';

  // Raw literals rather than the SDK constants that define them. All three are
  // at-rest values — what a writer stamped into a record's `appMetadata`, and
  // what a reader routes on — so comparing them against their own constants
  // would pin nothing. An intended change edits these three lines, and that
  // edit is the review.
  const xWingConveyanceId = 'at/nskey/XWING/AES/GCM';
  const mlKemConveyanceId = 'at/nskey/MLKEM1024/AES/GCM';
  const dataProviderId = 'at/symmetric/AES/GCM';

  const mlKemPlaintext = 'written after this install moved what it sends';
  const xWingPlaintext = 'written before it did';

  final storageDir = '${Directory.current.path}/test/hive/nskey_ladder_refusal';

  /// What the atServer holds, keyed by the at-key string `AtKey.toString()`
  /// renders — the form the pipeline-backed client matches a lookup against.
  final records = <String, WireRecord>{};

  /// Every remote command the sibling issued, so a read can be shown to have
  /// gone after the conveyance record rather than finding a content key
  /// somewhere else.
  final lookups = <String>[];

  late _WidenedRing ring;
  late AtClient sibling;
  late ({String conveyanceProviderId, String ckKid}) mlKemWrite;
  late ({String conveyanceProviderId, String ckKid}) xWingWrite;

  AtKey valueKey(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = alice
    ..metadata = Metadata();

  /// A record as the atServer serves it: the raw `metaData` object, with
  /// `appMetadata` as the base64 of its JSON, which is how it travels.
  Map<String, dynamic> wireMeta(AtKey key) => {
        'isEncrypted': true,
        'appMetadata': Metadata.encodeAppMetadata(key.metadata.appMetadata!),
      };

  /// Writes [name] the way an install willing to seal to [sealsTo], and to
  /// nothing else, writes it: the pre-pass mints a content key and conveys it,
  /// then the value is encrypted under it.
  ///
  /// The client is a mock because only its `put` is replaced. Everything that
  /// decides *what* gets written stays production code reached through
  /// `CryptoRuntime` — the resolver picking an entry out of the advertisement,
  /// the manager choosing which conveyance provider writes it, and both
  /// providers' `encrypt`. The stub runs that provider itself, so the record
  /// this leaves on the fixture atServer is the record production composes.
  ///
  /// Returns the conveyance's stamped provider id and the content key's kid,
  /// which is how each arm is told apart afterwards.
  Future<({String conveyanceProviderId, String ckKid})> writeAs(
      String name, String sealsTo, String plaintext) async {
    final config =
        CryptoConfig.nskey(keyRing: ring, sealsToKeyAlgorithms: [sealsTo]);
    final writer = MockAtClient();
    writer.getPreferences().crypto = config;
    when(() => writer.getCurrentAtSign()).thenReturn(alice);

    String? conveyanceProviderId;
    when(() => writer.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer(
      (invocation) async {
        final key = invocation.positionalArguments[0] as AtKey;
        final value = invocation.positionalArguments[1] as String;
        // The current-CK pointer is this install's own note to itself about
        // which content key it is writing under. Nothing here reads it, and it
        // arrives with no request options at all.
        if (key.key.startsWith('__ckcur')) return true;
        final options =
            invocation.namedArguments[#putRequestOptions] as PutRequestOptions;
        final provider = config.lookup(options.cryptoProviderId!)!;
        final wire =
            await provider.encrypt(CryptoContext(atClient: writer), key, value);
        conveyanceProviderId = key.metadata.appMetadata!.providerId;
        records[key.toString()] = WireRecord(wire, wireMeta(key));
        return true;
      },
    );

    final key = valueKey(name);
    final runtime = CryptoRuntime(writer);
    await runtime.prepareWrite(key, useRemoteAtServer: true);
    final ciphertext = await runtime.encryptForPut(key, plaintext);
    records[key.toString()] = WireRecord(ciphertext, wireMeta(key));

    return (
      conveyanceProviderId: conveyanceProviderId!,
      ckKid: key.metadata.appMetadata!.additional!['ckKid'] as String,
    );
  }

  setUpAll(() async {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeLookupVerbBuilder());
    AtClientImpl.atClientInstanceMap.clear();

    final xWingKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
    final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
    final xWingPair = await xWingKem.keyPairFromSeed(xWingKem.newSeed());
    final mlKemPair = await mlKem.keyPairFromSeed(mlKem.newSeed());

    // Both entries under one generation, X-Wing first — which is also the
    // order a build with no preference walks them in, so the older send
    // posture is the one that takes the first entry. The order is not
    // decoration: it is what the mutation named on the first test exploits.
    final advertised = NskeyAdvertisement(
      v: nskeyAdvertisementVersion,
      createdAt: DateTime.now().toUtc(),
      keys: [
        PackageKey.fromBytes(
            use: SecretSharingAlgos.useEnc,
            alg: SecretSharingAlgos.xWing,
            pub: xWingPair.publicKey),
        PackageKey.fromBytes(
            use: SecretSharingAlgos.useEnc,
            alg: SecretSharingAlgos.mlKem1024,
            pub: mlKemPair.publicKey),
      ],
    );
    ring = _WidenedRing(advertised, {
      advertised.keys[0].kid: xWingPair.secretKey,
      advertised.keys[1].kid: mlKemPair.secretKey,
    });

    xWingWrite = await writeAs(
        'sealed_to_xwing', SecretSharingAlgos.xWing, xWingPlaintext);
    mlKemWrite = await writeAs(
        'sealed_to_mlkem', SecretSharingAlgos.mlKem1024, mlKemPlaintext);

    // The sibling: the same key ring, so it holds the private for either
    // entry, and a provider set one conveyance scheme short. A hand-built
    // config is what makes the narrowing possible at all — the SDK's own
    // assembled set registers a conveyance provider per KEM on every client,
    // because a recipient's KEM is the recipient's choice.
    final siblingCache = ContentKeyCache();
    sibling = await buildPipelineBackedClient(
      atSign: alice,
      namespace: namespace,
      records: records,
      storagePath: storageDir,
      lookupLog: lookups,
      crypto: CryptoConfig(
        defaultProviderId: dataProviderId,
        providers: [
          SymmetricAesGcmProvider(cache: siblingCache),
          NskeyProvider(
              keyRing: ring,
              cache: siblingCache,
              keyAlgo: SecretSharingAlgos.xWing),
        ],
        keyRing: ring,
      ),
    );
  });

  tearDownAll(() async {
    try {
      // Both: a store given its own path opens its boxes on that path's Hive
      // instance, which the global close does not reach.
      await HiveInstances.closeAll();
      await Hive.close();
      AtClientImpl.atClientInstanceMap.clear();
      if (Directory(storageDir).existsSync()) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    } catch (_) {
      // Teardown must not mask a real failure in a test body.
    }
  });

  test(
      'a writer that seals only to ml-kem-1024 stamps the ml-kem conveyance '
      'provider', () async {
    // The two arms differ in one thing: which key-establishment algorithms
    // each writer was willing to seal to. Same advertisement, same key ring,
    // same namespace, same write sequence — so the ids below are the send
    // posture becoming visible on the wire and nothing else.
    //
    // Break-it, named and not applied: delete the `key.alg == alg` condition
    // from `NskeyAdvertisement.bestKeyFor`. The resolver then returns the
    // advertisement's first entry whatever algorithm was asked for — the
    // X-Wing one, in the order seeded above — so the ml-kem writer conveys
    // under the X-Wing provider and this assertion goes red naming the wrong
    // id. The refusal below goes red with it, because the sibling can then
    // open what that writer wrote; the control stays green, since asking for
    // X-Wing was already going to get the first entry.
    expect(mlKemWrite.conveyanceProviderId, mlKemConveyanceId,
        reason: 'a client that will seal to ml-kem-1024 and nothing else must '
            'convey its content key under the ml-kem provider — if it conveys '
            'under anything else, the record the arms below read is not the '
            'record this file is about');
    expect(xWingWrite.conveyanceProviderId, xWingConveyanceId,
        reason: 'and the other arm has to differ in exactly that and nothing '
            'else: the same ring and the same advertisement, sealed to by an '
            'install whose send side has not moved');
    expect(mlKemWrite.ckKid, isNot(xWingWrite.ckKid),
        reason: 'each write cut its own content key, so neither arm below can '
            'be satisfied by the other arm\'s conveyance');
  });

  test(
      'a sibling holding only the x-wing conveyance provider cannot open that '
      'record', () async {
    // Checked against the client rather than against the object handed to it,
    // because what decides a read is the config the client resolves.
    final configured = CryptoConfig.forClient(sibling);
    expect(configured.lookup(xWingConveyanceId), isNotNull,
        reason: 'this install must really hold the X-Wing conveyance provider, '
            'or the refusal below is a client that configures no post-quantum '
            'scheme at all rather than one algorithm short of its sibling');
    expect(configured.lookup(mlKemConveyanceId), isNull,
        reason: 'and it must really not hold the other one. A sibling that '
            'declined to use a provider it had would say something about how '
            'it was configured, not about a capability it never shipped');

    // The failure is raised on the nested read of the conveyance record, and
    // it has to survive that nesting: the conveyance read swallows almost
    // everything as "no such record", which would come back out as advice to
    // wait for a sync that has already happened. The message names the scheme
    // it is short of and the schemes it has — enough to say which build is
    // needed, though not which value was being read.
    await expectLater(
        () => sibling.get(valueKey('sealed_to_mlkem'),
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = true),
        throwsA(isA<CryptoProviderNotRegistered>()
            .having((e) => e.message, 'message', contains(mlKemConveyanceId))
            .having((e) => e.message, 'message', contains(xWingConveyanceId))),
        reason: 'an install one conveyance scheme short of its sibling cannot '
            'open what that sibling seals, and must say which scheme it is '
            'short of — not open the record, and not report it as a key that '
            'has yet to arrive');

    expect(lookups.where((c) => c.contains(mlKemWrite.ckKid)), isNotEmpty,
        reason: 'the read has to have reached the conveyance record to be '
            'refused by its provider id; if nothing fetched it, this arm is '
            'measuring a failure somewhere earlier');
  });

  test('the control: the same sibling opens a record sealed to x-wing',
      () async {
    // Essential, and able to stay green while the arm above goes red: without
    // it, an install that failed at every read would satisfy the refusal, and
    // a missing capability would be indistinguishable from a broken client.
    // Same install, same `get`, same conveyance mechanism — only the algorithm
    // its content key was sealed to differs.
    final read = await sibling.get(valueKey('sealed_to_xwing'),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);

    expect(read.value, xWingPlaintext,
        reason: 'this install is a working reader of everything sealed to the '
            'algorithm it does implement; if this is red the arm above '
            'measures a broken client rather than a capability it lacks');
    expect(read.metadata?.appMetadata?.providerId, dataProviderId,
        reason: 'and it routed on the record\'s own stamp, so the read really '
            'went through provider resolution');
    expect(lookups.where((c) => c.contains(xWingWrite.ckKid)), isNotEmpty,
        reason: 'the content key had to come from the conveyance record: this '
            'install started with an empty cache, so a read that never '
            'fetched one opened the value by some other route and is not the '
            'same mechanism the arm above refused');
  });
}

/// One nskey generation advertising two key-establishment algorithms, with the
/// private for each — an atSign that has widened what it can receive.
///
/// Built by hand because a mint writes one key and the in-memory ring models
/// that: the reader has to understand the two-entry shape before any writer
/// produces it, or the capability could never be turned on without breaking
/// every install that had not caught up.
class _WidenedRing implements NskeyKeyRing {
  _WidenedRing(this.advertised, this._privates);

  final NskeyAdvertisement advertised;
  final Map<String, Uint8List> _privates;

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      advertised;

  @override
  Future<NskeyDecapsulationKey?> privateHalf(
      String owner, String namespace, String nskeyKid) async {
    final secret = _privates[nskeyKid];
    return secret == null ? null : NskeyDecapsulationKey(secret);
  }
}
