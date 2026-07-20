import 'dart:convert';
import 'dart:typed_data';

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
      final sealedCk = await alice1.nskey
          .encrypt(context, conveyanceKey, ck.toBase64());

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
      expect(appMetadata.additional!['recipientKind'], NskeyRecipientKind.nskey);
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

      // A different nskey keypair seeded under the same namespace name — the
      // HPKE info binding plus the KEM must both refuse it.
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
    test('a data value arriving before its conveyance defers rather than '
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
        throwsA(isA<AtDecryptionException>()),
        reason: 'a cache miss is the deferred state, not a wrong plaintext',
      );

      // Once the conveyance syncs, the same read succeeds.
      await alice2.nskey
          .decrypt(context, ckConveyanceKey(ck.ckKid), await _seal(alice1, ck));
      expect(await alice2.data.decrypt(context, syncedValueKey, ciphertext),
          'the treaty text');
    });

    test('the CK cache is keyed by (owner, namespace, ckKid), never ckKid alone',
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

    test('evicting a rotated CK makes its data undecryptable, by design', () {
      final cache = ContentKeyCache();
      final ck = ContentKey(_randomKeyBytes());
      cache.put(owner, namespace, ck);
      cache.evict(owner, namespace, ck.ckKid);

      expect(cache.get(owner, namespace, ck.ckKid), isNull);
      expect(cache.current(owner, namespace), isNull);
    });
  });
}

/// Re-seal [ck] so a second client can consume its own copy of the conveyance.
Future<String> _seal(
  ({NskeyProvider nskey, SymmetricAesGcmProvider data, ContentKeyCache cache})
      client,
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
