/// A3 · E2EE within one atSign (self data) + self notification.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 4.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import 'blockers.dart';

void main() {
  group('A3 · self data', () {
    test('UC-A3.1 · self write/read, namespace key already exists', () async {
      // GIVEN @alice pq-native; the app_1.my_apps nskey exists and is published
      //       at public:__nskey.app_1.my_apps@alice; alice1, alice2 hold its
      //       private.
      // WHEN  alice1 does put <k>.app_1.my_apps@alice (shouldEncrypt).
      // THEN  alice2 syncs both records: at/nskey decapsulates the CK with the
      //       nskey private and caches it by ckKid; at/symmetric/AES/GCM
      //       resolves the CK by ckKid and AES-GCM-decrypts. Round-trip equals
      //       plaintext; a client lacking the nskey private cannot read. No
      //       legacy provider, no selfEncryptionKey.
      const owner = '@alice';
      const namespace = 'app_1.my_apps';
      const plaintext = 'the treaty text';

      final nskeyPair = await XWingKeyPair.generate();
      final context = CryptoContext(atClient: MockAtClient());

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

      AtKey key(String name) => AtKey()
        ..key = name
        ..namespace = namespace
        ..sharedBy = owner
        ..metadata = Metadata();

      final ck =
          ContentKey(Uint8List.fromList(base64Decode(AESKey.generate(32).key)));

      final alice1 = client();
      final conveyanceKey = key('${ck.ckKid}.__ck');
      final sealedCk =
          await alice1.nskey.encrypt(context, conveyanceKey, ck.toBase64());
      // Sealing a CK does not promote it — CkManager does that once the
      // conveyance write lands. Driving the providers directly means saying so.
      alice1.cache.putAsCurrent(owner, namespace, ck, alice1.nskeyKid);
      final valueKey = key('treaty');
      final ciphertext =
          await alice1.data.encrypt(context, valueKey, plaintext);

      // Both records reach alice2 carrying the appMetadata alice1 stamped —
      // for the conveyance that is what names the nskey generation it was
      // sealed to, and for the value it is the ckKid and iv.
      final alice2 = client();
      final syncedConveyance = key('${ck.ckKid}.__ck')
        ..metadata.appMetadata = conveyanceKey.metadata.appMetadata;
      await alice2.nskey.decrypt(context, syncedConveyance, sealedCk);
      final synced = key('treaty')
        ..metadata.appMetadata = valueKey.metadata.appMetadata;

      expect(await alice2.data.decrypt(context, synced, ciphertext), plaintext);
      expect(valueKey.metadata.appMetadata!.providerId,
          symmetricAesGcmCryptoProviderId);
    });

    test('UC-A3.2 · first self write in a namespace mints the nskey', () {
      // GIVEN @alice pq-native; no app_1.my_apps nskey exists in any form;
      //       alice1, alice2 PQ with registered key packages.
      // WHEN  alice1 does the first put <k>.app_1.my_apps@alice.
      // THEN  alice1 takes the _nskeylock mint lock, and
      //       public:__nskey.app_1.my_apps@alice is published immediately and
      //       resolves on a plookup — but an unauthenticated scan of @alice
      //       returns it under no circumstances, showhidden or not, which is
      //       what makes eager publication safe; alice2 obtains the private via
      //       the __ssenv push and reads; an app_2-only client is refused the
      //       app_1 private (server-gated); requestSecret is the pull backstop.
      fail('not implemented');
    }, skip: ss4);

    test('UC-A3.3 · self fallback to the atSign-level PQ key', () {
      // GIVEN @alice pq-native; alice1 wants self data but no
      //       nskey.app_1.my_apps@alice is minted and seal-and-hold is not
      //       chosen (send-now default).
      // WHEN  alice1 writes self data.
      // THEN  still the nskey data path, with the CK sealed to
      //       public:pqpublickey@alice (recipientKind: root-pqpublickey); the
      //       data value stays at/symmetric/AES/GCM citing ckKid — application
      //       data is NEVER encapsulated directly to pqpublickey. Any authorised
      //       enrollment reads; self-heals to the nskey on the first namespaced
      //       write.
      fail('not implemented');
    }, skip: b1);

    test('UC-A3.4 · self notification carrying an encrypted value', () {
      // GIVEN @alice pq-native; alice1, alice2 PQ; alice2 running a monitor.
      // WHEN  alice1 notifies @alice (self) with an encrypted value.
      // THEN  the notification value decrypts on alice2 with the same provider
      //       routing as a put; providerId travels ON THE NOTIFICATION FRAME,
      //       not only on stored keys; an offline alice2 still decrypts the
      //       queued notification on later delivery; a signal-only notification
      //       needs no decryption and is unaffected.
      fail('not implemented');
    }, skip: b1);
  });
}
