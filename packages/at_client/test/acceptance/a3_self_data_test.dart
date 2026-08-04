/// A3 · E2EE within one atSign (self data) + self notification.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 4.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import 'proven_elsewhere.dart';

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

    test('UC-A3.2 · a client mints the nskey for each authorised namespace',
        () {
      // GIVEN @alice pq-native; no app_1.my_apps nskey exists in any form;
      //       alice1, alice2 PQ with registered key packages.
      // WHEN  alice1 starts and seeds its authorised namespaces.
      // THEN  alice1 takes the _nskeylock mint lock, and
      //       public:__nskey.app_1.my_apps@alice is published immediately and
      //       resolves on a plookup — but an unauthenticated scan of @alice
      //       returns it under no circumstances, showhidden or not, which is
      //       what makes eager publication safe; alice2 obtains the private via
      //       the __ssenv push and reads; an app_2-only client is refused the
      //       app_1 private (server-gated); requestSecret is the pull backstop;
      //       and seeding is idempotent across starts.
      //
      // The catalogue used to trigger this on the first put. That was never
      // built and contradicted UC-A3.3 above, which requires a write to a
      // keyless namespace to FAIL and is proven live. Ruled 2026-08-04 that the
      // code was right — a put that minted would hide a lock, a keygen, a
      // publish and a conveyance behind one write — and acceptance.md 4.2 was
      // amended. See decisions.md 29.
      provenIn(
        'tests/at_functional_test/test/nskey_seeding_live_test.dart',
        'seeding publishes an advertisement the owner can then resolve',
        proves: 'against a namespace nothing has minted for, seed() reports '
            'minting it, the advertisement then resolves by the exact lookup a '
            'sender uses, the client holds the private for that generation, '
            'and a second seed is a no-op rather than a rotation',
      );
    });

    test('UC-A3.3 · self write with no namespace key has no PQ fallback', () {
      // GIVEN @alice pq-native; alice1 wants self data but no
      //       nskey.app_1.my_apps@alice is minted and seal-and-hold is not
      //       chosen (send-now default).
      // WHEN  alice1 writes self data.
      // THEN  the write FAILS. There is no atSign-level KEM to fall back on —
      //       the signing root signs and never receives an encapsulation — so a
      //       namespace with no nskey has no PQ path at all. The failure is a
      //       distinct exception naming the namespace, not a generic encryption
      //       error. With the legacy fallback opted in (final 3.x only) the
      //       write proceeds under legacy, and every SUBSEQUENT write uses the
      //       nskey once it exists; records already written stay legacy, and
      //       re-encrypting them is R-1's explicit migration. Rare in practice:
      //       a client mints for its preference namespace and its rw namespaces
      //       at init.
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_e2e_test.dart',
        'a write to a namespace with no nskey fails, saying which',
        proves:
            'cold start throws NamespaceKeyUnavailableException naming the atSign and namespace, with the readiness query and the opt-in legacy fallback covered alongside it',
      );
    });

    test('UC-A3.4 · self notification carrying an encrypted value', () async {
      // GIVEN @alice pq-native; alice1, alice2 PQ; alice2 running a monitor.
      // WHEN  alice1 notifies @alice (self) with an encrypted value.
      // THEN  the notification value decrypts on alice2 with the same provider
      //       routing as a put; providerId travels ON THE NOTIFICATION FRAME,
      //       not only on stored keys; an offline alice2 still decrypts the
      //       queued notification on later delivery; a signal-only notification
      //       needs no decryption and is unaffected.
      //
      // The frame is the whole point of this row. A stored key carries its
      // appMetadata in the record; a notification has to carry it in the
      // notification itself, and if it does not, the receiver has no way to
      // know which scheme opened the value it was just handed.
      const providerId = symmetricAesGcmCryptoProviderId;
      final provider = _RecordingProvider(providerId);
      final client = MockAtClient();
      client.getPreferences().crypto =
          CryptoConfig(defaultProviderId: providerId, providers: [provider]);

      Map<String, dynamic> frame({String? value}) => {
            'id': 'abc-123',
            'key': '@alice:treaty.app_1.my_apps@alice',
            'from': '@alice',
            'to': '@alice',
            // Well in the past: an alice2 that was offline receives exactly
            // this frame later, so a transform that consulted arrival time
            // would be the thing that broke queued delivery.
            'epochMillis': 1600000000000,
            'messageType': 'MessageType.key',
            'isEncrypted': value != null,
            if (value != null) 'value': value,
            'metadata': {
              AtConstants.appMetadata: base64Encode(utf8.encode(jsonEncode({
                'providerId': providerId,
                'ckKid': 'a1b2c3d4e5f60718',
                'iv': base64Encode(List<int>.filled(16, 7)),
              }))),
            },
          };

      // 1. providerId travels ON THE FRAME — decoded off the notification's
      //    own metadata, not looked up from any stored record.
      final parsed = AtNotification.fromJson(frame(value: 'ciphertext'));
      expect(parsed.metadata?.appMetadata?.providerId, providerId,
          reason: 'without this the receiver holds a value and no idea which '
              'scheme opens it — stored keys would work and notifications '
              'would not, which is exactly the shape of a silent data loss');
      expect(parsed.metadata?.appMetadata?.additional,
          containsPair('ckKid', 'a1b2c3d4e5f60718'),
          reason: 'the per-record entries have to ride along too; a providerId '
              'with no ckKid names a scheme that then cannot find its key');

      // 2. Routed by that id, the same way a put is.
      final delivered =
          await NotificationResponseTransformer(client).transform(Tuple()
            ..one = parsed
            ..two = (NotificationConfig()
              ..regex = '.*'
              ..shouldDecrypt = true));

      expect(provider.decryptCalls, 1,
          reason: 'the notification value must reach the provider the FRAME '
              'names, not the client\'s default and not legacy');
      expect(delivered.value, '$providerId decrypted ciphertext');

      // 3. A signal-only notification carries no value, so there is nothing to
      //    decrypt and the provider must not be troubled. This is the control:
      //    it shows the call count above tracks the value, not the transform.
      final signal = AtNotification.fromJson(frame());
      await NotificationResponseTransformer(client).transform(Tuple()
        ..one = signal
        ..two = (NotificationConfig()
          ..regex = '.*'
          ..shouldDecrypt = true));

      expect(provider.decryptCalls, 1,
          reason: 'a signal-only notification is unaffected — if this went to '
              '2, every signal notification is attempting a decryption of '
              'nothing');
    });
  });
}

/// Names itself in its output, so a routing assertion cannot pass by reaching
/// the wrong provider and getting a plausible-looking string back.
class _RecordingProvider implements CryptoProvider {
  @override
  final String id;

  int decryptCalls = 0;

  _RecordingProvider(this.id);

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String plaintext) async =>
      '$id encrypted $plaintext';

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    decryptCalls++;
    return '$id decrypted $ciphertext';
  }
}
