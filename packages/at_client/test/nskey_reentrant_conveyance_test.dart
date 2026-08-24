// The nskey substrate is @experimental; driving it is the point.
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_commons/at_commons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The re-entrant conveyance read: a value whose content key is NOT cached.
///
/// `SymmetricAesGcmProvider.decrypt` resolves a missing CK by calling
/// `context.atClient.get(<ckKid>.__ck…)` from inside the value's own decrypt,
/// and **discards the result** — the key arrives only as a side effect of the
/// nested read populating the cache. Every other test of this provider seeds
/// the cache first, so that path has never run under test: with an unstubbed
/// `MockAtClient`, the nested `get` returns null, `read()` swallows it, and the
/// resolve reports the CK unavailable.
///
/// What it pins is the outer call's contract: after resolving a CK through a
/// nested read, the outer decrypt must return **the value's** plaintext, not
/// the content key the nested read produced.
///
/// ⚠️ This is a **narrower** claim than the live defect it was written for.
/// Measured 2026-08-24 against a real atServer, an outer `get` came back
/// holding the conveyance record's 44-character content key and its
/// `at/nskey/XWING/AES/GCM` metadata while the atServer held the value record
/// correctly. That crosses `AtClientImpl.get` and `GetResponseTransformer`,
/// which no unit fixture drives — `buildRemoteBackedMockClient` stubs
/// `AtClient.get` outright. So a green here does not clear the read path; it
/// narrows where the fault can be.
void main() {
  const owner = '@alice';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair nskeyPair;

  setUpAll(() async {
    nskeyPair = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  ({
    NskeyProvider nskey,
    SymmetricAesGcmProvider data,
    ContentKeyCache cache,
    String nskeyKid,
  }) client() {
    final cache = ContentKeyCache();
    final ring = InMemoryNskeyKeyRing();
    final kid = ring.seedKeypair(owner, namespace,
        publicKey: nskeyPair.publicKeyBytes,
        privateKey: nskeyPair.privateKeyBytes);
    return (
      nskey: NskeyProvider(keyRing: ring, cache: cache),
      data: SymmetricAesGcmProvider(cache: cache),
      cache: cache,
      nskeyKid: kid,
    );
  }

  CryptoContext contextFor(MockAtClient atClient) {
    when(() => atClient.getCurrentAtSign()).thenReturn(owner);
    return CryptoContext(atClient: atClient);
  }

  AtKey dataKey(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = owner
    ..metadata = Metadata();

  test('a value whose CK is resolved by a nested read decrypts to the VALUE',
      () async {
    const plaintext = 'the treaty text';

    // The writer holds the CK and stamps the value record.
    final writer = client();
    final writerContext = contextFor(MockAtClient());
    final ck =
        ContentKey(Uint8List.fromList(base64Decode(AESKey.generate(32).key)));
    final conveyanceKey = AtKey()
      ..key = '${ck.ckKid}.__ck'
      ..namespace = namespace
      ..sharedBy = owner
      ..metadata = Metadata();
    final sealedCk =
        await writer.nskey.encrypt(writerContext, conveyanceKey, ck.toBase64());
    writer.cache.putAsCurrent(owner, namespace, ck, writer.nskeyKid);

    final valueKey = dataKey('treaty');
    final ciphertext =
        await writer.data.encrypt(writerContext, valueKey, plaintext);

    // The reader has never seen the CK, so the outer decrypt must resolve it
    // through the nested read rather than from cache.
    final reader = client();
    final readerClient = MockAtClient();
    final readerContext = contextFor(readerClient);
    expect(reader.cache.get(owner, namespace, ck.ckKid), isNull,
        reason: 'the reader must start without the content key, or the nested '
            'read this test exists to exercise never happens');

    // The nested read, modelled the way production behaves: the conveyance
    // record arrives carrying the appMetadata its writer stamped, and opening
    // it caches the CK. `_resolveFromConveyance` discards the returned value,
    // so the cache write is the whole effect.
    var nestedReads = 0;
    Future<AtValue> nested(Invocation inv) async {
      nestedReads++;
      final asked = inv.positionalArguments[0] as AtKey;
      final synced = AtKey()
        ..key = asked.key
        ..namespace = asked.namespace
        ..sharedBy = asked.sharedBy
        ..metadata =
            (Metadata()..appMetadata = conveyanceKey.metadata.appMetadata);
      final opened =
          await reader.nskey.decrypt(readerContext, synced, sealedCk);
      return AtValue()
        ..value = opened
        ..metadata = synced.metadata;
    }

    when(() => readerClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer(nested);
    when(() => readerClient.get(any())).thenAnswer(nested);

    // The value record as it reaches the reader: the writer's stamp travels.
    final synced = dataKey('treaty')
      ..metadata = (Metadata()..appMetadata = valueKey.metadata.appMetadata);
    final opened = await reader.data.decrypt(readerContext, synced, ciphertext);

    expect(nestedReads, greaterThan(0),
        reason: 'the CK was resolved without a nested read, so this test '
            'measured the cache rather than the path it names');
    expect(opened, plaintext,
        reason: 'the outer decrypt returned the nested read\'s content key '
            'instead of the value it was asked for. Live, that surfaces as a '
            '44-character base64 string where a record\'s payload should be, '
            'with no exception raised');
    expect(opened, isNot(ck.toBase64()),
        reason: 'named explicitly because this is the exact wrong value the '
            'live failure produced');
  });
}
