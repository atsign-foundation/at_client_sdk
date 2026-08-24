// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/pipeline_backed_client.dart';

/// The read pipeline itself, driven end to end.
///
/// Every other unit test reaches `AtClient.get` through a fixture that stubs
/// it, so `GetResponseTransformer` — where a response becomes an [AtValue],
/// picks a crypto provider from the record's own `appMetadata`, and decrypts —
/// has never run under test.
///
/// It was written while a wrong-value read measured against a live atServer in
/// 2026-08 was unexplained and this layer was the obvious suspect. It was not
/// the cause — that read turned out to be an atServer answering two concurrent
/// cross-atSign lookups with each other's responses, below at_client
/// entirely — but the coverage gap is real on its own account, and this is the
/// only test that closes it.
///
/// The case here is the one that failed live: a value whose content key is not
/// cached, so decrypting it makes a **nested** `get` for the `<ckKid>.__ck`
/// conveyance record from inside the outer read's own decrypt. The outer
/// [AtValue] must come back holding the value's plaintext and the value
/// record's metadata — not the conveyance record's.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';
  final storageDir = '${Directory.current.path}/test/hive/pipeline';

  late XWingKeyPair nskeyPair;

  setUpAll(() async {
    nskeyPair = await XWingKeyPair.generate();
    registerFallbackValue(FakeLookupVerbBuilder());
    registerFallbackValue(AtKey());
  });

  setUp(() => AtClientImpl.atClientInstanceMap.remove(atSign));

  tearDown(() async {
    try {
      await Hive.close();
      AtClientImpl.atClientInstanceMap.clear();
      if (Directory(storageDir).existsSync()) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    } catch (_) {
      // Teardown must not mask a real failure in the test body.
    }
  });

  // Both assertions below are mutation-proven, one mutation each, because a
  // green that cannot fail is worth nothing:
  //
  //  - the VALUE assertion: make `SymmetricAesGcmProvider.decrypt` return
  //    `ck.toBase64()`. Red, quoting the plaintext against a 44-character
  //    base64 — the live failure's shape.
  //  - the METADATA assertion: have that same decrypt stamp
  //    `atKey.metadata.appMetadata` with the nskey provider. Red, quoting
  //    `at/symmetric/AES/GCM` against `at/nskey/XWING/AES/GCM` — the live
  //    values exactly.
  //
  // ⚠️ The second works because `GetResponseTransformer` assigns
  // `atValue.metadata` and `tuple.one.metadata` **the same object**, so an
  // in-place `appMetadata` mutation on the AtKey during a read is visible on
  // the returned `AtValue`. That aliasing is a live hazard, not a quirk of the
  // mutation: any code holding the caller's AtKey can change what a completed
  // read appears to have returned.
  test('a value whose CK needs a nested conveyance read returns the VALUE',
      () async {
    const plaintext = 'the treaty text';

    // --- what the writer put on the atServer ---------------------------
    final writerCache = ContentKeyCache();
    final writerRing = InMemoryNskeyKeyRing();
    final writerKid = writerRing.seedKeypair(atSign, namespace,
        publicKey: nskeyPair.publicKeyBytes,
        privateKey: nskeyPair.privateKeyBytes);
    final writerNskey = NskeyProvider(keyRing: writerRing, cache: writerCache);
    final writerData = SymmetricAesGcmProvider(cache: writerCache);

    final writerClient = MockAtClient();
    when(() => writerClient.getCurrentAtSign()).thenReturn(atSign);
    final writerContext = CryptoContext(atClient: writerClient);

    final ck =
        ContentKey(Uint8List.fromList(base64Decode(AESKey.generate(32).key)));
    final conveyanceKey = AtKey()
      ..key = '${ck.ckKid}.__ck'
      ..namespace = namespace
      ..sharedBy = atSign
      ..metadata = Metadata();
    final sealedCk =
        await writerNskey.encrypt(writerContext, conveyanceKey, ck.toBase64());
    writerCache.putAsCurrent(atSign, namespace, ck, writerKid);

    final valueKey = AtKey()
      ..key = 'treaty'
      ..namespace = namespace
      ..sharedBy = atSign
      ..metadata = Metadata();
    final ciphertext =
        await writerData.encrypt(writerContext, valueKey, plaintext);

    // The two records, as the atServer serves them. `metaData` is built the
    // way the wire carries it — appMetadata base64 of its JSON — so the
    // fixture pins the bytes rather than a Dart object's shape.
    Map<String, dynamic> wireMeta(AtKey key) => {
          'isEncrypted': true,
          'appMetadata': Metadata.encodeAppMetadata(key.metadata.appMetadata!),
        };
    final records = <String, WireRecord>{
      valueKey.toString(): WireRecord(ciphertext, wireMeta(valueKey)),
      conveyanceKey.toString(): WireRecord(sealedCk, wireMeta(conveyanceKey)),
    };

    // --- a reader that has never seen the content key -------------------
    final readerCache = ContentKeyCache();
    final readerRing = InMemoryNskeyKeyRing();
    readerRing.seedKeypair(atSign, namespace,
        publicKey: nskeyPair.publicKeyBytes,
        privateKey: nskeyPair.privateKeyBytes);
    expect(readerCache.get(atSign, namespace, ck.ckKid), isNull,
        reason: 'the reader must start without the content key, or the nested '
            'read this test exists to drive never happens');

    final lookups = <String>[];
    final client = await buildPipelineBackedClient(
      atSign: atSign,
      namespace: namespace,
      records: records,
      storagePath: storageDir,
      lookupLog: lookups,
      crypto: CryptoConfig(
        defaultProviderId: symmetricAesGcmCryptoProviderId,
        providers: [
          SymmetricAesGcmProvider(cache: readerCache),
          NskeyProvider(keyRing: readerRing, cache: readerCache),
        ],
        keyRing: readerRing,
      ),
    );

    final read = await client.get(valueKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);

    expect(lookups.where((c) => c.contains('__ck')), isNotEmpty,
        reason: 'no conveyance record was fetched, so the content key came '
            'from somewhere else and this test measured the wrong path');

    expect(read.value, plaintext,
        reason: 'the outer get returned something other than the value it was '
            'asked for. Live, this surfaces as a 44-character base64 content '
            'key with no exception raised');
    expect(read.value, isNot(ck.toBase64()),
        reason: 'named explicitly: the content key is the exact wrong value '
            'the live failure produced');
    expect(
        read.metadata?.appMetadata?.providerId, symmetricAesGcmCryptoProviderId,
        reason: 'the outer AtValue must carry the VALUE record\'s metadata. '
            'Live it carried the conveyance record\'s, naming the at/nskey '
            'provider and its ckKid');
  });
}
