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

      provenIn(
        'packages/at_client/test/nskey_data_path_test.dart',
        'alice1 writes, alice2 syncs both records and round-trips plaintext',
        proves: 'the two-hop routing as the clause states it — the conveyance '
            'opens with the nskey private and the content key is cached under '
            'its ckKid, then the value resolves that same ckKid and '
            'AES-GCM-decrypts. The hops are driven separately, so a build '
            'that opened the value some other way would not satisfy it',
        clauses: ['the `at/nskey` provider decapsulates the CK with the nskey '
            'private and caches it by `ckKid`'],
      );
      provenIn(
        'packages/at_client/test/nskey_data_path_test.dart',
        'a client lacking the nskey private cannot decapsulate the CK',
        proves: 'the exclusion arm, which is the half that makes the rest '
            'mean anything: a client holding everything except the nskey '
            'private fails to open the conveyance and therefore cannot read '
            'the value. Without it the row is satisfied by a build that '
            'ignores the nskey entirely',
        clauses: ['a client lacking the nskey private cannot decapsulate the '
            'CK and so cannot read'],
      );
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
          clauses: [
            'a later start adopts the published advertisement rather than '
            'minting over it',
          ]);
      provenIn(
        'tests/at_functional_test/test/underscore_public_key_hiding_test.dart',
        'a public:__ key syncs, is served by plookup, and is not enumerable',
        proves: 'what makes eager publication safe, against the atServer that '
            'decides it: the record answers a plookup — so a sender can '
            'always fetch it — while an unauthenticated scan does not list '
            'it, with and without showhidden. Both halves are needed; a '
            'record that were merely unreachable would fail the first',
        clauses: ['an unauthenticated `scan` of `@alice`, with and without '
            '`showhidden`, returns no'],
      );
      provenIn(
        'tests/at_functional_test/test/enrollment_namespace_gate_test.dart',
        'a scoped enrollment cannot read the envelope channel of a namespace ',
        proves: 'the server-side gate, with both controls: the atServer '
            'refuses the scoped enrollment\'s read of the withheld '
            'namespace\'s channel and the refusal names that namespace, while '
            'the same enrollment still receives envelopes in the namespace it '
            'was granted and the approver can read the withheld one. A mocked '
            'lookup cannot produce this refusal at all',
        clauses: ['client is refused the `app_1.my_apps` nskey private '
            '(server-gated on the `__ssenv` channel)'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_self_heal_live_test.dart',
        'an enrollment that missed the mint pulls the private from a holder',
        proves: 'the pull backstop end to end against a live atServer: the '
            'seeker is shown to genuinely lack the private and to see the '
            'published generation, the holder is primed, the request is '
            'observed going out, and the private arrives in the seeker\'s '
            'keyfile byte-exact under the generation already advertised — so '
            'it healed rather than minting a rival',
        clauses: ['`requestSecret` is the pull backstop for an enrollment '
            'offline during the push'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a second write reuses the content key rather than cutting a new one',
        proves: 'that a later write into a namespace that already has a key '
            'uses it rather than minting: the second put carries the same '
            'ckKid as the first and cuts no new conveyance record. A build '
            'that re-minted per write would still round-trip, so the reuse '
            'has to be asserted rather than inferred from success',
        clauses: ['A subsequent `put` into the namespace uses the key that '
            'already exists; it does not mint'],
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
      //       re-encrypting them is an explicit migration (B-3's lazy
      //       re-encrypt; R-1 delivered no migration machinery). Rare in practice:
      //       a client mints for its preference namespace and its rw namespaces
      //       at init.
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a write to a namespace with no nskey fails, saying which',
        proves:
            'cold start throws NamespaceKeyUnavailableException naming the atSign and namespace, with the readiness query and the opt-in legacy fallback covered alongside it',
      );
      provenIn(
        'packages/at_client/test/nskey_seeding_test.dart',
        'an enrolled client seeds the namespaces its enrollment grants',
        proves: 'why the cold-start case is rare rather than routine: a '
            'client seeds each namespace its own enrollment grants at start, '
            'so the namespaces it is entitled to write already hold a key by '
            'the time a put arrives. The rarity is a property of what seeding '
            'covers, not a hope',
        clauses: ['In practice this case is rare, because a client mints for '
            'its preference namespace'],
      );
      provenIn(
        'packages/at_client/test/cold_start_test.dart',
        'a self write to an unminted namespace refuses the same way',
        proves: 'the exception TYPE and where it is raised, which the live '
            'test cannot separate from any other failure of the same put: the '
            'refusal is NamespaceKeyUnavailableException carrying the atSign '
            'and namespace, and it comes from the CK-manager pre-pass rather '
            'than from a provider failing mid-encrypt',
        clauses: ['the exception is `NamespaceKeyUnavailableException(atSign, '
            'namespace)`, raised by the CK-manager pre-pass'],
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

      // The four clauses above are established against a hand-built frame, so
      // they show what the receive path does with a frame rather than that a
      // real atServer produces one. The live test carries the two clauses that
      // difference matters for.
      provenIn(
          'tests/at_functional_test/test/nskey_self_notify_live_test.dart',
          'a self notification reaches a second enrollment and decrypts',
          proves: 'both clauses against a real atServer and a genuinely '
              'second enrollment: the delivered frame carries providerId in '
              'its own appMetadata, and the value opens with the nskey '
              'private conveyed at approval. A mocked frame can show neither '
              '— it hands the receiver a value it never had to decrypt, and '
              'a providerId the test itself wrote',
          clauses: [
            'same provider routing as a put',
            'on the notification frame',
          ]);
    });

    test('UC-A3.5 · the nskey advertisement names its KEM and what it opens',
        () {
      // GIVEN alice1 authorised for app_1.my_apps; the deployment configured
      //       for one of the two key-establishment algorithms.
      // WHEN  alice1 mints and publishes the namespace key (as UC-A3.2).
      // THEN  the signed advertisement carries alg AND suites beside
      //       {v, nskeyKid, publicKey}. alg is not decorative: a sender cannot
      //       tell an X-Wing encapsulation key from an ML-KEM one by looking,
      //       and encapsulating under the wrong KEM produces a conveyance the
      //       owner can never open. A conveyance is sealed under the KEM alg
      //       names and stamped with the matching provider id; BOTH ids are
      //       registered on every client whatever this atSign mints, because a
      //       recipient's KEM is the recipient's choice — writes route by the
      //       destination's advertised algorithm, reads by the id the record
      //       already carries, so neither KEM's conveyances stop opening and
      //       there is no flag day. An advertisement with no alg reads as the
      //       hybrid, which is what every one published before the field was by
      //       construction; one naming an algorithm this build cannot
      //       encapsulate to is refused, not guessed at. suites then makes the
      //       conveyance VERSION negotiated: 0x02 for an owner that lists RFC
      //       9180, 0x01 for one whose advertisement predates the field, 0x03
      //       for ML-KEM-1024, and a refusal when nothing overlaps.
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'ML-KEM-1024 conveys under its own provider id at ver 0x03',
        proves: 'the write side end to end — the destination\'s advertised alg '
            'selects the provider id and the seal version, asserted on the '
            'envelope\'s first byte rather than on a label. Its siblings carry '
            'the negotiation arms ("the hybrid negotiates RFC 9180 with an '
            'owner that advertises it" against "and refuses an owner that '
            'only opens the retired construction", both against the same key) '
            'and the refusals ("no shared construction is a refusal, not a '
            'guess"; "a provider will not seal to the other KEM").',
          clauses: [
            'a CK conveyance into that namespace is sealed under the KEM '
            '`alg` names and stamped',
          ]);
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'both ids resolve on every client',
        proves: 'the no-flag-day property: every client registers a conveyance '
            'provider for BOTH KEMs whatever it mints itself, and the two ids '
            'are distinct so reads route apart while sharing one content-key '
            'cache. Without this a recipient choosing the other KEM would be '
            'unreachable from anyone who had not also switched.',
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'the published advertisement emits its exact wire shape — raw literals',
        proves: 'the advertised document as bytes rather than as a round '
            'trip: the emitted body is pinned against hand-written literals, '
            'so suites sits beside each entry\'s alg in the shape senders '
            'parse. A round-trip through the writer\'s own reader would stay '
            'green for a shape no other build could read',
        clauses: ['the APKAM-signed advertisement carries **`suites`** beside '
            'each entry\'s **`alg`**'],
      );
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'and refuses an owner that only opens the retired construction',
        proves: 'that the seal version follows the owner\'s advertised KEM '
            'rather than the sender\'s preference, and that an owner sharing '
            'no live construction is refused instead of being guessed at. The '
            'refusal arm is what stops the selection reading as a default',
        clauses: ['An X-Wing owner therefore receives `ver 0x02` and an '
            'ML-KEM-1024 owner `ver 0x03`'],
      );
    });
  });
}

/// Names itself in its output, so a routing assertion cannot pass by reaching
/// the wrong provider and getting a plausible-looking string back.
///
/// Extends rather than implements: a member added to [CryptoProvider] with a
/// body reaches a subclass, while an implementer silently loses it and fails
/// at runtime with nothing the analyzer can say.
class _RecordingProvider extends CryptoProvider {
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
