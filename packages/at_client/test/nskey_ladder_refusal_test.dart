/// An install that never shipped one of the post-quantum key-establishment
/// algorithms, reading a record a sibling of the same atSign wrote under it.
///
/// Both installs hold every private the namespace advertises, so the sibling's
/// missing conveyance provider is the only available explanation for the
/// refusal it raises.
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

  // NOTE: raw literals rather than the SDK constants that define them. All
  // three are at-rest values, so comparing them against their own constants
  // would pin nothing; an intended change edits these three lines.
  const xWingConveyanceId = 'at/nskey/XWING/AES/GCM';
  const mlKemConveyanceId = 'at/nskey/MLKEM1024/AES/GCM';
  const dataProviderId = 'at/symmetric/AES/GCM';

  const mlKemPlaintext = 'written after this install moved what it sends';
  const xWingPlaintext = 'written before it did';

  final storageDir = '${Directory.current.path}/test/hive/nskey_ladder_refusal';

  /// What the atServer holds, keyed by the at-key string `AtKey.toString()`
  /// renders — the form the pipeline-backed client matches a lookup against.
  final records = <String, WireRecord>{};

  /// Every remote command the sibling issued.
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
  /// Returns the conveyance's stamped provider id and the content key's kid.
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
        // NOTE: the current-CK pointer arrives with no request options at all,
        // so it has to return before the cast below.
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

    // NOTE: X-Wing first is not decoration — a walk with no preference takes
    // the first entry, which is what makes the ml-kem arm discriminate.
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
    // entry, and a provider set one conveyance scheme short.
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
      // NOTE: both — a store given its own path opens its boxes on that path's
      // Hive instance, which the global close does not reach.
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
    final configured = CryptoConfig.forClient(sibling);
    expect(configured.lookup(xWingConveyanceId), isNotNull,
        reason: 'this install must really hold the X-Wing conveyance provider, '
            'or the refusal below is a client that configures no post-quantum '
            'scheme at all rather than one algorithm short of its sibling');
    expect(configured.lookup(mlKemConveyanceId), isNull,
        reason: 'and it must really not hold the other one. A sibling that '
            'declined to use a provider it had would say something about how '
            'it was configured, not about a capability it never shipped');

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
/// Built by hand because a mint writes one key.
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
