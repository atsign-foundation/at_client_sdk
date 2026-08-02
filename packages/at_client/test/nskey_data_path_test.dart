import 'dart:convert';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_commons/at_commons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The nskey data path, driven end to end with the namespace key supplied by a
/// fixture instead of the secret-sharing substrate.
///
/// This is the walking skeleton for UC-A3.1. It proves the two providers and
/// the CK cache compose into a working self-data round-trip, which is what the
/// substrate work later feeds for real — the production path (a minted nskey,
/// its private conveyed per-APKAM) is unchanged by anything here.
void main() {
  const owner = '@alice';
  const namespace = 'app_1.my_apps';

  late CryptoContext context;
  late XWingKeyPair nskeyPair;

  /// A client of @alice authorised for the namespace: holds both halves.
  ({NskeyProvider nskey, SymmetricAesGcmProvider data, ContentKeyCache cache})
      authorisedClient() {
    final cache = ContentKeyCache();
    final ring = InMemoryNskeyKeyRing()
      ..seedKeypair(owner, namespace,
          publicKey: nskeyPair.publicKeyBytes,
          privateKey: nskeyPair.privateKeyBytes);
    return (
      nskey: NskeyProvider(keyRing: ring, cache: cache),
      data: SymmetricAesGcmProvider(cache: cache),
      cache: cache,
    );
  }

  AtKey ckConveyanceKey(String ckKid) => AtKey()
    ..key = '$ckKid.__ck'
    ..namespace = namespace
    ..sharedBy = owner
    ..metadata = Metadata();

  AtKey dataKey(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = owner
    ..metadata = Metadata();

  setUpAll(() async {
    // One nskey keypair per (atSign, namespace) — the recipient key for both
    // directions. Minted once for the whole suite; minting is not what this
    // exercises.
    nskeyPair = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  setUp(() {
    final mockAtClient = MockAtClient();
    when(() => mockAtClient.getCurrentAtSign()).thenReturn(owner);
    context = CryptoContext(atClient: mockAtClient);
  });

  group('UC-A3.1 · self write/read, namespace key already exists', () {
    test('alice1 writes, alice2 syncs both records and round-trips plaintext',
        () async {
      const plaintext = 'the treaty text';

      // --- alice1 writes -------------------------------------------------
      final alice1 = authorisedClient();

      // 1. Cut a symmetric CK.
      final ck = ContentKey(_randomKeyBytes());

      // 2. Convey the CK once: sealed to @alice's own nskey, written as its own
      //    <ckKid>.__ck record.
      final conveyanceKey = ckConveyanceKey(ck.ckKid);
      final sealedCk =
          await alice1.nskey.encrypt(context, conveyanceKey, ck.toBase64());

      // 3. Write the data value under that CK.
      final valueKey = dataKey('treaty');
      final ciphertext =
          await alice1.data.encrypt(context, valueKey, plaintext);

      // --- alice2 syncs and reads ----------------------------------------
      // A distinct client: its own cache, seeded only with the namespace
      // keypair it received. It has never seen the CK.
      final alice2 = authorisedClient();
      expect(alice2.cache.get(owner, namespace, ck.ckKid), isNull,
          reason: 'alice2 must start without the content key');

      // at/nskey decapsulates the CK with the nskey private and caches it.
      final recoveredCk = await alice2.nskey
          .decrypt(context, ckConveyanceKey(ck.ckKid), sealedCk);
      expect(recoveredCk, ck.toBase64());

      // at/symmetric/AES/GCM resolves the CK by ckKid and decrypts.
      final syncedValueKey = dataKey('treaty')
        ..metadata.appMetadata = valueKey.metadata.appMetadata;
      final recovered =
          await alice2.data.decrypt(context, syncedValueKey, ciphertext);

      expect(recovered, plaintext, reason: 'round-trip must equal plaintext');
    });

    test('the data value cites a ckKid and carries no sealed key inline',
        () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      await alice1.nskey
          .encrypt(context, ckConveyanceKey(ck.ckKid), ck.toBase64());

      final valueKey = dataKey('treaty');
      await alice1.data.encrypt(context, valueKey, 'the treaty text');

      final appMetadata = valueKey.metadata.appMetadata!;
      expect(appMetadata.providerId, symmetricAesGcmCryptoProviderId);
      expect(appMetadata.additional!['ckKid'], ck.ckKid);
      expect(appMetadata.additional!['iv'], isNotNull);
      expect(appMetadata.additional!.containsKey('sealedKey'), isFalse,
          reason: 'decision (a): the CK is conveyed once, never inline');
      expect(appMetadata.additional!.containsKey('ns'), isFalse,
          reason: 'appMetadata carries no ns field');
    });

    test('the CK conveyance record is tagged at/nskey with recipientKind nskey',
        () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      final conveyanceKey = ckConveyanceKey(ck.ckKid);
      await alice1.nskey.encrypt(context, conveyanceKey, ck.toBase64());

      final appMetadata = conveyanceKey.metadata.appMetadata!;
      expect(appMetadata.providerId, nskeyCryptoProviderId);
      expect(
          appMetadata.additional!['recipientKind'], NskeyRecipientKind.nskey);
      expect(appMetadata.additional!['ckKid'], ck.ckKid);
      expect(appMetadata.additional!.containsKey('iv'), isFalse,
          reason: 'the pqSeal envelope carries its own kemCt and nonce');
    });

    test('a client lacking the nskey private cannot decapsulate the CK',
        () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      final sealedCk = await alice1.nskey
          .encrypt(context, ckConveyanceKey(ck.ckKid), ck.toBase64());

      // An @alice client authorised for a different namespace only: it holds no
      // private half for app_1.my_apps.
      final outsider = NskeyProvider(
        keyRing: InMemoryNskeyKeyRing(),
        cache: ContentKeyCache(),
      );

      await expectLater(
        outsider.decrypt(context, ckConveyanceKey(ck.ckKid), sealedCk),
        throwsA(isA<AtDecryptionException>()),
      );
    });

    test('a wrong namespace key cannot open the conveyance', () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      final sealedCk = await alice1.nskey
          .encrypt(context, ckConveyanceKey(ck.ckKid), ck.toBase64());

      // A different nskey keypair under the same namespace name, so the info
      // bytes match on both sides and it is the KEM alone that refuses it.
      // The info binding is covered separately, one keypair across two
      // namespaces.
      final wrongPair = await XWingKeyPair.generate();
      final wrongRing = InMemoryNskeyKeyRing()
        ..seedKeypair(owner, namespace,
            publicKey: wrongPair.publicKeyBytes,
            privateKey: wrongPair.privateKeyBytes);
      final wrongClient =
          NskeyProvider(keyRing: wrongRing, cache: ContentKeyCache());

      await expectLater(
        wrongClient.decrypt(context, ckConveyanceKey(ck.ckKid), sealedCk),
        throwsA(isA<AtDecryptionException>()),
      );
    });
  });

  group('CK resolution & ordering', () {
    test(
        'a data value arriving before its conveyance defers rather than '
        'failing silently', () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      await alice1.nskey
          .encrypt(context, ckConveyanceKey(ck.ckKid), ck.toBase64());
      final valueKey = dataKey('treaty');
      final ciphertext =
          await alice1.data.encrypt(context, valueKey, 'the treaty text');

      // alice2 has the namespace key but the __ck record has not synced yet.
      final alice2 = authorisedClient();
      final syncedValueKey = dataKey('treaty')
        ..metadata.appMetadata = valueKey.metadata.appMetadata;

      await expectLater(
        alice2.data.decrypt(context, syncedValueKey, ciphertext),
        throwsA(isA<ContentKeyUnavailableException>()
            .having((e) => e.ckKid, 'ckKid', ck.ckKid)),
        reason: 'a cache miss is the deferred state, not a wrong plaintext — '
            'and it is typed, so a caller can tell retry-later from give-up',
      );

      // Once the conveyance syncs, the same read succeeds.
      await alice2.nskey
          .decrypt(context, ckConveyanceKey(ck.ckKid), await _seal(alice1, ck));
      expect(await alice2.data.decrypt(context, syncedValueKey, ciphertext),
          'the treaty text');
    });

    test('a conveyance already in local storage is opened on demand', () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      final sealedCk = await alice1.nskey
          .encrypt(context, ckConveyanceKey(ck.ckKid), ck.toBase64());
      final valueKey = dataKey('treaty');
      final ciphertext =
          await alice1.data.encrypt(context, valueKey, 'the treaty text');

      // alice2 has the __ck record locally but has never opened it, so its
      // cache is cold. Reading the record routes back through at/nskey.
      final alice2 = authorisedClient();
      final mockAtClient = MockAtClient();
      when(() => mockAtClient.getCurrentAtSign()).thenReturn(owner);
      when(() => mockAtClient.get(any())).thenAnswer((invocation) async {
        final requested = invocation.positionalArguments.first as AtKey;
        expect(requested.key, '${ck.ckKid}.__ck');
        expect(requested.namespace, namespace);
        expect(requested.sharedBy, owner);
        await alice2.nskey.decrypt(context, requested, sealedCk);
        return AtValue();
      });
      final localContext = CryptoContext(atClient: mockAtClient);

      final syncedValueKey = dataKey('treaty')
        ..metadata.appMetadata = valueKey.metadata.appMetadata;
      expect(
          await alice2.data.decrypt(localContext, syncedValueKey, ciphertext),
          'the treaty text');
    });

    test('an older conveyance opened later does not become the write key',
        () async {
      final alice1 = authorisedClient();
      final oldCk = ContentKey(_randomKeyBytes());
      final newCk = ContentKey(_randomKeyBytes());

      // alice1 cuts and conveys two CKs in order; the second is current.
      await alice1.nskey
          .encrypt(context, ckConveyanceKey(oldCk.ckKid), oldCk.toBase64());
      final sealedOld = await _seal(alice1, oldCk);
      await alice1.nskey
          .encrypt(context, ckConveyanceKey(newCk.ckKid), newCk.toBase64());
      expect(alice1.cache.current(owner, namespace)!.ckKid, newCk.ckKid);

      // Sync has no order, so the older conveyance can arrive afterwards.
      await alice1.nskey
          .decrypt(context, ckConveyanceKey(oldCk.ckKid), sealedOld);

      expect(alice1.cache.current(owner, namespace)!.ckKid, newCk.ckKid,
          reason: 'an arriving conveyance is cached, never made current — '
              'otherwise new writes silently roll back onto a superseded CK');
      expect(alice1.cache.get(owner, namespace, oldCk.ckKid), isNotNull,
          reason: 'the old CK still resolves for data written under it');
    });

    test(
        'the CK cache is keyed by (owner, namespace, ckKid), never ckKid alone',
        () {
      final cache = ContentKeyCache();
      final ck = ContentKey(_randomKeyBytes());
      cache.put(owner, namespace, ck);

      expect(cache.get(owner, namespace, ck.ckKid), isNotNull);
      expect(cache.get(owner, 'app_2.my_apps', ck.ckKid), isNull,
          reason: 'kids are unique within a namespace, not across them');
      expect(cache.get('@bob', namespace, ck.ckKid), isNull,
          reason: 'identity is (owner, id), never id alone');
    });

    test('two different CKs claiming one kid is refused, not silently merged',
        () {
      final cache = ContentKeyCache();
      final ck = ContentKey(_randomKeyBytes());
      cache.put(owner, namespace, ck);

      // Re-delivery of the same CK is ordinary and must stay idempotent.
      cache.put(owner, namespace, ContentKey(Uint8List.fromList(ck.bytes)));
      expect(cache.get(owner, namespace, ck.ckKid), isNotNull);

      // A genuine kid collision would make the displaced CK's data
      // undecryptable, so it fails loudly instead.
      expect(() => cache.put(owner, namespace, _CollidingKey(ck.ckKid)),
          throwsA(isA<StateError>()));
    });

    test('evicting a rotated CK makes its data undecryptable, by design', () {
      final cache = ContentKeyCache();
      final ck = ContentKey(_randomKeyBytes());
      cache.putAsCurrent(owner, namespace, ck);
      expect(cache.current(owner, namespace), isNotNull);

      cache.evict(owner, namespace, ck.ckKid);

      expect(cache.get(owner, namespace, ck.ckKid), isNull);
      expect(cache.current(owner, namespace), isNull);
    });
  });

  group('envelope and payload handling', () {
    test('the same nskey cannot open a conveyance sealed for another namespace',
        () async {
      // One keypair, two namespaces — isolating the HPKE info binding from the
      // KEM, which a wrong-keypair test cannot do.
      final ring = InMemoryNskeyKeyRing()
        ..seedKeypair(owner, namespace,
            publicKey: nskeyPair.publicKeyBytes,
            privateKey: nskeyPair.privateKeyBytes)
        ..seedKeypair(owner, 'app_2.my_apps',
            publicKey: nskeyPair.publicKeyBytes,
            privateKey: nskeyPair.privateKeyBytes);
      final provider = NskeyProvider(keyRing: ring, cache: ContentKeyCache());

      final ck = ContentKey(_randomKeyBytes());
      final sealedForApp1 = await provider.encrypt(
          context, ckConveyanceKey(ck.ckKid), ck.toBase64());

      final asApp2 = AtKey()
        ..key = '${ck.ckKid}.__ck'
        ..namespace = 'app_2.my_apps'
        ..sharedBy = owner
        ..metadata = Metadata();

      await expectLater(
        provider.decrypt(context, asApp2, sealedForApp1),
        throwsA(isA<AtDecryptionException>()),
        reason: 'info binds the key schedule to (owner, namespace), so the '
            'same private cannot reinterpret the envelope as another namespace',
      );
    });

    test('a malformed envelope surfaces as AtDecryptionException', () async {
      final alice = authorisedClient();
      for (final bad in [
        'not base64 at all!',
        base64Encode([1, 2, 3])
      ]) {
        await expectLater(
          alice.nskey
              .decrypt(context, ckConveyanceKey('deadbeefdeadbeef'), bad),
          throwsA(isA<AtDecryptionException>()),
          reason: 'the provider contract holds whatever the envelope is',
        );
      }
    });

    test('a binary value round-trips byte-exact', () async {
      final alice1 = authorisedClient();
      final ck = ContentKey(_randomKeyBytes());
      await alice1.nskey
          .encrypt(context, ckConveyanceKey(ck.ckKid), ck.toBase64());

      // Every byte value, plus a length that does not fall on a 15-bit boundary.
      final bytes = Uint8List.fromList(
          [for (var i = 0; i < 256; i++) i, 0x00, 0xff, 0x7f]);
      final asString = Base2e15.encode(bytes);

      final valueKey = dataKey('blob')..metadata.isBinary = true;
      final ciphertext = await alice1.data.encrypt(context, valueKey, asString);

      final alice2 = authorisedClient();
      await alice2.nskey
          .decrypt(context, ckConveyanceKey(ck.ckKid), await _seal(alice1, ck));
      final synced = dataKey('blob')
        ..metadata.isBinary = true
        ..metadata.appMetadata = valueKey.metadata.appMetadata;

      final recovered = await alice2.data.decrypt(context, synced, ciphertext);
      expect(Base2e15.decode(recovered), bytes,
          reason: 'binary must survive the round-trip byte for byte');
      expect(recovered, asString);
    });
  });
}

/// A [ContentKey] forced to claim a kid it did not derive, so the cache's
/// collision guard can be exercised — a real 64-bit collision is unreachable.
class _CollidingKey implements ContentKey {
  @override
  final String ckKid;

  @override
  final Uint8List bytes = _randomKeyBytes();

  _CollidingKey(this.ckKid);

  @override
  String toBase64() => base64Encode(bytes);
}

/// Re-seal [ck] so a second client can consume its own copy of the conveyance.
Future<String> _seal(
  ({
    NskeyProvider nskey,
    SymmetricAesGcmProvider data,
    ContentKeyCache cache
  }) client,
  ContentKey ck,
) async {
  final key = AtKey()
    ..key = '${ck.ckKid}.__ck'
    ..namespace = 'app_1.my_apps'
    ..sharedBy = '@alice'
    ..metadata = Metadata();
  final mockAtClient = MockAtClient();
  when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
  return client.nskey
      .encrypt(CryptoContext(atClient: mockAtClient), key, ck.toBase64());
}

Uint8List _randomKeyBytes() =>
    Uint8List.fromList(base64Decode(AESKey.generate(32).key));
