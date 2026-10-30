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
      // NOTE: driving the providers directly skips CK promotion, so the
      // content key has to be promoted by hand here.
      alice1.cache.putAsCurrent(owner, namespace, ck, alice1.nskeyKid);
      final valueKey = key('treaty');
      final ciphertext =
          await alice1.data.encrypt(context, valueKey, plaintext);

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
        clauses: [
          'the `at/nskey` provider decapsulates the CK with the nskey '
              'private and caches it by `ckKid`'
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_data_path_test.dart',
        'a client lacking the nskey private cannot decapsulate the CK',
        proves: 'the exclusion arm, which is the half that makes the rest '
            'mean anything: a client holding everything except the nskey '
            'private fails to open the conveyance and therefore cannot read '
            'the value. Without it the row is satisfied by a build that '
            'ignores the nskey entirely',
        clauses: [
          'a client lacking the nskey private cannot decapsulate the '
              'CK and so cannot read'
        ],
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
      provenIn('tests/at_functional_test/test/nskey_seeding_live_test.dart',
          'seeding publishes an advertisement the owner can then resolve',
          proves: 'against a namespace nothing has minted for, seed() reports '
              'minting it, the advertisement then resolves by the exact lookup a '
              'sender uses, the client holds the private for that generation, '
              'and a second seed is a no-op rather than a rotation',
          clauses: [
            'a later start adopts the published advertisement rather than '
                'minting over it',
            'exists and resolves on a `plookup`',
          ]);
      provenIn('tests/at_functional_test/test/nskey_self_notify_live_test.dart',
          'a self notification reaches a second enrollment and decrypts',
          proves: 'the second half of the same clause — a SECOND enrollment '
              'of this atSign fetching a stored self record from the '
              'atServer and opening it with the nskey private conveyed to it '
              'at approval. The record is checked to be on the nskey data '
              'path first, without which the read passes for a legacy self '
              'write that every enrollment can open because the self '
              'encryption key is atSign-wide. ⚠️ Nothing in the tree paired '
              'those two before 2026-08-28: every multi-enrollment read was '
              'cross-atSign, and the self direction was only ever a '
              'notification',
          clauses: [
            'exists and resolves on a `plookup`',
          ]);
      provenIn(
        'tests/at_functional_test/test/nskey_conveyance_reach_live_test.dart',
        'a key minted in a namespace reaches every enrollment with access to '
            'it, a * enrollment included',
        proves: 'against the atServer that decides the roster: an enrollment '
            'granted only `*`, and one granted read on the namespace above, '
            'are listed as members and are each conveyed the key minted at '
            'the namespace and the one minted below it, while an enrollment '
            'granted only another namespace is neither listed nor conveyed '
            'either. A client pushes to whatever `enroll:listns` answers, so '
            'only a live atServer can say who that is',
        clauses: [
          'a `*` enrollment and one granted a namespace above it included',
        ],
      );
      provenIn(
        'tests/at_functional_test/test/underscore_public_key_hiding_test.dart',
        'a public:__ key syncs, is served by plookup, and is not enumerable',
        proves: 'what makes eager publication safe, against the atServer that '
            'decides it: the record answers a plookup — so a sender can '
            'always fetch it — while an unauthenticated scan does not list '
            'it, with and without showhidden. Both halves are needed; a '
            'record that were merely unreachable would fail the first',
        clauses: [
          'an unauthenticated `scan` of `@alice`, with and without '
              '`showhidden`, returns no'
        ],
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
        clauses: [
          'client is refused the `app_1.my_apps` nskey private '
              '(server-gated on the `__ssenv` channel)'
        ],
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
        clauses: [
          '`requestSecret` is the pull backstop for an enrollment '
              'offline during the push'
        ],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a second write reuses the content key rather than cutting a new one',
        proves: 'that a later write into a namespace that already has a key '
            'uses it rather than minting: the second put carries the same '
            'ckKid as the first and cuts no new conveyance record. A build '
            'that re-minted per write would still round-trip, so the reuse '
            'has to be asserted rather than inferred from success',
        clauses: [
          'A subsequent `put` into the namespace uses the key that '
              'already exists; it does not mint'
        ],
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
      //       error. With the legacy fallback opted in (any posture below pqActive) the
      //       write proceeds with the legacy provider, and every SUBSEQUENT write uses the
      //       nskey once it exists; records already written stay legacy-encrypted, and
      //       re-encrypting them is an explicit migration. Rare in practice:
      //       a client mints for its preference namespace and its rw namespaces
      //       at init.
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a write to a namespace with no nskey fails, saying which',
        proves:
            'cold start throws NamespaceKeyUnavailableException naming the atSign and namespace, with the readiness query and the opt-in legacy fallback covered alongside it',
      );
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a namespace that gains a key takes over, and what the fallback wrote',
        proves: 'the fallback clause on every arm it states, live and in one '
            'run: with the escape hatch open a write to a keyless namespace '
            'goes out with the legacy provider; the namespace then GAINS a key and the very next '
            'write uses it, with no opt-in and no flag to flip; and the record '
            'the fallback already wrote comes back legacy and readable, so '
            'nothing was re-encrypted behind a later put. ⚠️ The middle arm '
            'was FALSE until 2026-08-27, not merely untested — the fallback '
            'write warmed a remembered miss in NskeyResolver, so the key '
            'appearing changed nothing for the rest of that window. '
            'Mutation-proven: reverting that fix leaves the later write on '
            'legacy, quoting this assertion, while the control — a second '
            'write taken BEFORE the key exists, which must stay legacy-encrypted — is '
            'green, so the flip is attributed to the key appearing rather '
            'than to writing twice',
        clauses: [
          'Records already written under the fallback stay legacy-encrypted'
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_seeding_test.dart',
        'an enrolled client seeds the namespaces its enrollment grants',
        proves: 'why the cold-start case is rare rather than routine: a '
            'client seeds each namespace its own enrollment grants at start, '
            'so the namespaces it is entitled to write already hold a key by '
            'the time a put arrives. The rarity is a property of what seeding '
            'covers, not a hope',
        clauses: [
          'In practice this case is rare, because a client mints for '
              'its preference namespace'
        ],
      );
      provenIn(
        'packages/at_client/test/cold_start_test.dart',
        'a self write to an unminted namespace refuses the same way',
        proves: 'the exception TYPE and where it is raised, which the live '
            'test cannot separate from any other failure of the same put: the '
            'refusal is NamespaceKeyUnavailableException carrying the atSign '
            'and namespace, and it comes from the CK-manager pre-pass rather '
            'than from a provider failing mid-encrypt',
        clauses: [
          'the exception is `NamespaceKeyUnavailableException(atSign, '
              'namespace)`, raised by the CK-manager pre-pass'
        ],
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
            // NOTE: deliberately well in the past — an offline alice2 receives
            // this frame later, so arrival time must not steer the transform.
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

      final parsed = AtNotification.fromJson(frame(value: 'ciphertext'));
      expect(parsed.metadata?.appMetadata?.providerId, providerId,
          reason: 'without this the receiver holds a value and no idea which '
              'scheme opens it — stored keys would work and notifications '
              'would not, which is exactly the shape of a silent data loss');
      expect(parsed.metadata?.appMetadata?.additional,
          containsPair('ckKid', 'a1b2c3d4e5f60718'),
          reason: 'the per-record entries have to ride along too; a providerId '
              'with no ckKid names a scheme that then cannot find its key');

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

      provenIn('tests/at_functional_test/test/nskey_self_notify_live_test.dart',
          'a self notification reaches a second enrollment and decrypts',
          proves: 'three clauses against a real atServer and a genuinely '
              'second enrollment: the delivered frame carries providerId in '
              'its own appMetadata, and the value opens with the nskey '
              'private conveyed at approval. A mocked frame can show neither '
              '— it hands the receiver a value it never had to decrypt, and '
              'a providerId the test itself wrote. The offline clause is the '
              'same file\'s last arm: the receiving enrollment\'s monitor '
              'socket is destroyed, the sender notifies over its own verb '
              'connection, and the value arrives and decrypts after the '
              'reconnect. ⚠️ That arm was unwritable until the two '
              'enrollments could hold separate stores — a shared store is a '
              'shared replay watermark, and the SENDER\'s monitor received '
              'the notification and advanced it past what the receiver had '
              'missed. Putting both enrollments back on one path reddens it '
              'with exactly that diagnosis',
          clauses: [
            'same provider routing as a put',
            'on the notification frame',
            'still decrypts on later delivery',
          ]);
      provenHere(
        proves: 'the signal-only arm, asserted above: a notification carrying '
            'no value leaves the decrypt count unchanged. If it rose, every '
            'signal notification would be attempting to decrypt nothing — '
            'which fails quietly rather than loudly, so the count is the only '
            'thing that shows it',
        clauses: [
          'A signal-only notification (no value) needs no decryption '
              'and is unaffected'
        ],
      );
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
      //       conveyance CONSTRUCTION negotiated: x-wing-rfc9180-v1 for an
      //       owner that lists RFC 9180, a refusal for one whose
      //       advertisement predates the field, ml-kem-1024-rfc9180-v1
      //       for ML-KEM-1024, and a refusal when nothing overlaps.
      provenIn('packages/at_client/test/nskey_kem_selection_test.dart',
          'ML-KEM-1024 conveys under its own provider id at ver 0x03',
          proves:
              'the write side end to end — the destination\'s advertised alg '
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
        clauses: [
          'the APKAM-signed advertisement carries **`suites`** beside '
              'each entry\'s **`alg`**'
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'and refuses an owner that only opens the retired construction',
        proves: 'that the seal version follows the owner\'s advertised KEM '
            'rather than the sender\'s preference, and that an owner sharing '
            'no live construction is refused instead of being guessed at. The '
            'refusal arm is what stops the selection reading as a default',
        clauses: ['An X-Wing owner therefore receives `x-wing-rfc9180-v1`'],
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'an advertisement missing any required field is refused',
        proves: 'that an entry with no `alg` is dropped rather than defaulted: '
            'the loop removes each of use, alg, pub and kid from the entry in '
            'turn and the reader refuses what is left, with the control — the '
            'same payload intact — resolving, so the loop fails on the '
            'removal and not on the fixture. The sibling "an advertisement of '
            'only unusable entries is refused" covers the algorithm this '
            'build cannot encapsulate to',
        clauses: ['an entry with **no `alg`** is **dropped, not defaulted**'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_filing_test.dart',
        'the correspondence check follows the advertised KEM, not X-Wing',
        proves: 'that the re-derivation follows the advertisement rather than '
            'assuming X-Wing. Every other arm of this check advertises '
            'X-Wing, where following and assuming are the same computation '
            'and so indistinguishable; this one advertises ML-KEM-1024, where '
            'a build assuming X-Wing derives a different-length public half '
            'and REFUSES a private that corresponds exactly. Mutation-proven '
            '— pinning the algorithm to X-Wing reddens it, quoting this '
            'assertion',
        clauses: [
          're-derives the public half **through the advertised KEM** '
              'rather than assuming X-Wing'
        ],
      );
    });

    test(
        'UC-A3.6 · a client that needs a private it does not hold fetches it, '
        'else asks, else fails', () {
      // GIVEN an own nskey generation published, whose private this
      //       enrollment's client has not filed.
      // WHEN  it writes or reads in that namespace.
      // THEN  for a generation an own advertisement it holds names, it fetches
      //       the conveyance records addressed to it, files a private one
      //       carries, and goes on; with none, it asks the other enrollments
      //       and the put fails saying the private key has not yet been
      //       conveyed. For a generation none it holds names, it first reads
      //       the published advertisement, once per askCooldown per namespace
      //       and only in a namespace it holds an advertisement or a private
      //       for. It asks about each generation once per askCooldown and not
      //       while an earlier ask for it waits, and with askOnReadMiss off a
      //       miss sends nothing.
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when a conveyance record for it is waiting, then the fetch files it',
        proves: 'the fetch comes first and a record it finds is filed and '
            'used, with nothing asked. Mutation-proven: removing the fetch '
            'from privateHalf reddens it with a null private',
        clauses: ['it fetches the conveyance records addressed to it'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_fetch_on_miss_live_test.dart',
        'a client that started before the key was minted fetches the record '
            'waiting for it at its first write',
        proves: 'against a live atServer: a client whose listener is stopped '
            'and whose keyfile holds nothing for the generation writes, '
            'reads the value back, and has filed the private the waiting '
            'record carried',
        clauses: ['it fetches the conveyance records addressed to it'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when no record is waiting, then it asks and holds nothing',
        proves: 'with nothing waiting the ring asks, after the fetch',
        clauses: ['asks the other enrollments'],
      );
      provenIn(
        'packages/at_client/test/nskey_data_path_test.dart',
        'a served public half alone is refused, by name',
        proves: 'the refusal names the generation and says the private key '
            'has not yet been conveyed to this enrollment',
        clauses: ['has not yet been conveyed to this enrollment'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when two misses come at once, then one fetch serves both',
        proves: 'two misses in flight share one fetch, and the second reads '
            'only after it lands',
        clauses: ['concurrent misses share one fetch'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when fifty come at once over three namespaces, then one fetch serves '
            'them all and each generation is asked once',
        proves: 'fifty misses over six advertised generations in three '
            'namespaces make one fetch and six asks. Mutation-proven: stamping '
            'asks per namespace reddens it with three',
        clauses: [
          'whichever generations they name',
          'asks about each generation at most once per',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when kid A misses and then kid B in one namespace, then both are '
            'asked',
        proves: 'a second generation in a namespace gets its own ask, with A '
            'missed twice and asked once as the control. Mutation-proven: '
            'stamping asks per namespace reddens it with B unasked',
        clauses: ['a miss on a second generation in the namespace asks'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when a generation misses again while its ask is outstanding',
        proves: 'with no cooldown, a miss while the ask is outstanding asks '
            'nothing, and once its wait ends the next miss asks. '
            'Mutation-proven: dropping the outstanding check reddens it with '
            'two asks',
        clauses: ['not again while an earlier ask for it'],
      );
      provenIn(
        'packages/at_client/test/nskey_self_heal_test.dart',
        'a start with a missing kid sends exactly one ask, and a read miss '
            'inside the wait adds none',
        proves: 'the start sends one request and its wait holds back a read '
            'miss with no cooldown, until the wait ends. Mutation-proven: the '
            'start reading through privateHalf, and the start not recording '
            'its ask, each redden it',
        clauses: ['from a miss or from the client\'s start'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the cooldown has passed, then the next miss asks again and the '
            'quiet namespaces are forgotten',
        proves: 'past the cooldown a generation is asked again, and only the '
            'stamps inside it are held. Mutation-proven: dropping the prune '
            'reddens it with three',
        clauses: ['forgets a generation once its cooldown has passed'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the ring knows nothing of its namespace, then nothing is read',
        proves: 'twenty misses in namespaces the ring holds nothing for read, '
            'fetch and ask nothing. Mutation-proven: treating every namespace '
            'as known reddens it with twenty reads',
        clauses: ['only in a namespace whose own advertisement it holds'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the ring holds its own advertisement for the namespace, then it '
            'reads the published one once per cooldown',
        proves: 'forty misses on unnamed kids make one read, no fetch and no '
            'ask, and a miss past the cooldown reads again. Mutation-proven: '
            'dropping the read cooldown, and fetching for an unnamed kid, each '
            'redden it',
        clauses: ['it first reads'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the keyfile holds a private for the namespace and the published '
            'advertisement names a newer generation',
        proves: 'a miss on a newer generation in a namespace only the keyfile '
            'holds reads once, then fetches and asks, with a namespace the '
            'keyfile does not hold as the control. Mutation-proven: dropping '
            'the keyfile from what the ring knows reddens it with no read',
        clauses: ['whose nskey private its keyfile holds'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when its first read in a granted namespace comes before its startup '
            'collection',
        proves: 'a fresh enrollment whose keyfile records only its grants '
            'reads the published advertisement on its first miss and files '
            'the conveyance waiting for it. Mutation-proven: dropping the '
            'grants from what the ring knows reddens it with a null private',
        clauses: ['or which this enrollment\'s own grants name'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when it reads in a namespace outside its grants',
        proves: 'a namespace the grants do not name is read, fetched and '
            'asked nothing. Mutation-proven: counting any grant as naming '
            'every namespace reddens it',
        clauses: ['or which this enrollment\'s own grants name'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when its grant is `*`, then a namespace no grant names',
        proves: 'a `*` grant makes no namespace known. Mutation-proven: '
            'letting `*` name every namespace reddens it',
        clauses: ['never `*`'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the client is the atSign\'s own credential',
        proves: 'grants recorded under `primary` make no namespace known. '
            'Mutation-proven: letting the credential\'s grants count '
            'reddens it',
        clauses: ['never for the atSign\'s own credential'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the atServer cannot be reached at the first miss',
        proves: 'a read that fails is not retried inside the cooldown, and the '
            'first miss after it reads, fetches and opens. Mutation-proven: a '
            'read stamp that never expires reddens it',
        clauses: ['tried again by the first miss after the cooldown'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when the ring is built with askOnReadMiss false',
        proves: 'neither an unnamed kid in a keyfile namespace nor an '
            'advertised one reaches the atServer, with the same ring built '
            'with the gate on as the control. Mutation-proven: ignoring the '
            'gate reddens it',
        clauses: ['a miss sends nothing to the atServer'],
      );
      provenIn(
        'packages/at_client/test/pq_client_bootstrap_test.dart',
        'when the gates are inert, then a miss on it makes no call',
        proves: 'through the bootstrap over a keyfile, an inert start and then '
            'a miss on an advertised generation make no remote read, write or '
            'scan, with the gate on as the control beside it. '
            'Mutation-proven: ignoring the gate reddens it',
        clauses: ['a miss sends nothing to the atServer'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when it misses again within askCooldown of an on-miss fetch',
        proves: 'the cooldown bounds the fetch, with a zero-cooldown control '
            'beside it that fetches twice',
        clauses: ['does not fetch again'],
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'a sweep that meets an envelope another sweep is filing returns only',
        proves: 'a fetch that meets an envelope the startup collection is '
            'still filing waits for it, so the write after it finds the '
            'private. Mutation-proven: skipping the wait reddens it',
        clauses: ['for a sweep already filing it'],
      );
      provenIn(
        'packages/at_client/test/nskey_private_fetch_test.dart',
        'when a write seals to its own key, then it is refused once '
            'fetchOnMissTimeout passes',
        proves: 'a write whose fetch is still filing is refused when the '
            'bound passes, observed by the fetch being unfinished and the '
            'timeout path logging, and the same write seals once the filing '
            'lands. Mutation-proven: without the bound the write never '
            'returns',
        clauses: ['for a sweep already filing it'],
      );
    });

    test(
        'UC-A3.7 · a namespace key\'s private reaches every listed enrollment '
        'before anyone can seal to it', () {
      // GIVEN E1, E2 and E3 hold rw on app_1.my_apps with verified key
      //       packages, primary is listed with none, nothing is published.
      // WHEN  E1 mints, rotates or adds a key.
      // THEN  every new private is conveyed before the advertisement names it,
      //       primary is skipped silently and a refused package is named, the
      //       lock's ttl is a roster-sized ceiling, a revocation in the window
      //       stops the publish and retires the generation, a client meeting
      //       the lock mints and retires nothing, and a minter with no key
      //       package mints nothing; a minted root is pushed once published.
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a mint, a rotation and an add convey their new privates before the '
            'advertisement naming them is published',
        proves: 'each conveyance runs while the atServer still serves the '
            'previous advertisement, for a mint, a rotation and an add. '
            'Mutation-proven: moving the conveyance after the publish reddens '
            'it',
        clauses: [
          'is on the atServer before `public:__nskey.app_1.my_apps@alice` '
              'names it'
        ],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_fetch_on_miss_live_test.dart',
        'a client that started before the key was minted fetches the record '
            'waiting for it at its first write',
        proves: 'the atServer stored each conveyance record addressed to the '
            'other enrollment before it stored the advertisement, by the '
            'createdAt it stamps on both',
        clauses: [
          'is on the atServer before `public:__nskey.app_1.my_apps@alice` '
              'names it'
        ],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when it conveys, then every kid is pushed before anything returns',
        proves: 'the conveyance a mint is handed pushes every new private to '
            'the roster before it returns',
        clauses: [
          'is on the atServer before `public:__nskey.app_1.my_apps@alice` '
              'names it'
        ],
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'when a secret is pushed to the namespace, then it is named and the '
            'rest are still reached',
        proves: 'a member whose package was refused is named in a warning and '
            'conveyed nothing, while primary, listed with no package, is '
            'skipped without one. Mutation-proven: removing the refused arm '
            'reddens it',
        clauses: [
          '`primary` among them, is skipped silently',
          'is conveyed nothing and named in a warning',
        ],
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'when a listed member shares no suite with the minter, then the '
            'conveyance completes',
        proves: 'convey returns with the generation conveyed, the reachable '
            'member holds the private, and one warning names the member it '
            'missed, the generation and the namespace. Mutation-proven: '
            'dropping the warning, and letting one member\'s failure stop the '
            'push, each redden it',
        clauses: ['the push cannot reach'],
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'when the push to a listed member fails, then the conveyance '
            'completes',
        proves: 'the same, for a member whose envelope the atServer refuses. '
            'Mutation-proven as above',
        clauses: ['the push cannot reach'],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when the lock is sized, then it is the margin plus the budget for '
            'each listed enrollment',
        proves: 'the ttl is the margin plus the per-member budget for each '
            'listed enrollment, each kid and each conveyance, and is capped '
            'at the atServer\'s limit. Mutation-proven: sizing for one '
            'conveyance reddens it',
        clauses: ['the mint lock\'s ttl is a ceiling'],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a mint, a rotation and an add take the lock with the ttl handed them',
        proves: 'each operation takes its lock with the ttl it is handed. '
            'Mutation-proven for all three: falling back to the ring\'s own '
            'ttl reddens it',
        clauses: ['the mint lock\'s ttl is a ceiling'],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a mint that overruns its lease publishes nothing',
        proves: 'a minter whose lease has run out does not publish',
        clauses: ['the mint lock\'s ttl is a ceiling'],
      );
      provenIn(
        'packages/at_client/test/nskey_seed_lock_covers_rotation_test.dart',
        'when a client seeds it, then the mint lock lasts for two conveyances',
        proves: 'a seed sizes its lock for the mint\'s conveyance and a '
            'rotation\'s under the same lock, and an add for one',
        clauses: ['the mint lock\'s ttl is a ceiling'],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when a revocation touches the namespace during the conveyance, then '
            'the publish is refused and what it filed is retired',
        proves: 'a revocation read after the conveyance refuses the publish '
            'and retires the filed generation, with the no-revocation control '
            'beside it',
        clauses: [
          'stops the publish, and the generation E1 filed is retired',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a conveyance that throws publishes nothing',
        proves: 'the refusal the conveyance throws reaches the mint before '
            'its publish, so nothing is advertised',
        clauses: [
          'stops the publish, and the generation E1 filed is retired',
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'when this client filed a generation it then failed to publish',
        proves: 'the next mint publishes a fresh kid, conveys only that kid, '
            'and retires the filed one, which still reads. Mutation-proven: '
            'restoring a resume, or dropping the retire, reddens it',
        clauses: ['a mint that finds nothing published always mints'],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'when another enrollment conveyed this client a generation and never '
            'published it',
        proves: 'a private conveyed through file() and never published is '
            'retired, and the mint publishes a kid of its own',
        clauses: ['whichever enrollment minted it'],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'when a second process of this enrollment mints while the first is '
            'conveying',
        proves: 'a second ring on the same keyfile meets the first\'s lock, '
            'throws without minting, and leaves the first\'s filed generation '
            'active; once the first publishes, a fresh ring holds it and seals '
            'to it. Mutation-proven: adopting a refused lock, or one whose '
            'value names this enrollment, reddens it',
        clauses: ['mints nothing and retires nothing while the lock is held'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_mint_lock_live_test.dart',
        'a client that meets a lock naming its own enrollment refuses to mint',
        proves: 'a lock on the atServer whose value is this client\'s own '
            'enrollment id refuses its mint, and nothing is published',
        clauses: ['mints nothing and retires nothing while the lock is held'],
      );
      provenIn(
        'packages/at_client/test/mint_lock_self_contention_test.dart',
        'when a new instance of the same enrollment asks for it',
        proves: 'a fresh MintLock of the enrollment that took the lock is '
            'refused without reading it. Mutation-proven as above',
        clauses: ['refused until the lock\'s ttl runs out'],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when a revocation touches the namespace after the conveyance read '
            'it',
        proves: 'the keyfile records the owed rotation before the rotation, '
            'which conveys a successor afresh, with the no-revocation control '
            'beside it. Mutation-proven: missing the revocation, or skipping '
            'the record, reddens it',
        clauses: [
          'a revocation landing after that read and before the publish'
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'when the mint publishes, then the rotation publishes under the same '
            'lock',
        proves: 'one lock take, two publishes, and the successor conveyed '
            'between them. Mutation-proven: skipping afterPublish, or '
            'conveying nothing, reddens it',
        clauses: [
          'a revocation landing after that read and before the publish'
        ],
      );
      provenIn(
        'packages/at_client/test/nskey_seeding_test.dart',
        'when its record stamp is later than the revocation, then it is '
            'rotated',
        proves: 'a start rotates a published generation the keyfile records '
            'as owed, though its stamp answers the revocation, and not once '
            'its successor is published. Mutation-proven: ignoring the '
            'record, or reading any record in the namespace, reddens it',
        clauses: ['E1\'s next start makes the rotation'],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when the rotation fails, then the generation published stands',
        proves: 'a rotation that throws after the publish answers no '
            'successor, keeps the record and logs the namespace at severe. '
            'Mutation-proven: rethrowing reddens it with the failure, and '
            'logging below severe reddens it',
        clauses: ['the mint still answers the generation it published'],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when this enrollment no longer carries a key package to convey a '
            'successor with',
        proves: 'with the minter\'s own package gone at the fresh prepare, '
            'nothing rotates, the record stays and the failure is logged at '
            'severe. Mutation-proven: throwing when the prepare finds no '
            'package reddens it',
        clauses: ['the mint still answers the generation it published'],
      );
      provenIn(
        'packages/at_client/test/pre_publish_conveyance_test.dart',
        'when it seeds, then it answers noKeyPackage and mints nothing',
        proves: 'a minter whose own entry carries no key package asks the '
            'ring for no mint',
        clauses: ['mints nothing and says why'],
      );
      provenIn(
        'packages/at_client/test/seeding_files_private_test.dart',
        'when its roster entry carries none, then it answers noKeyPackage and '
            'publishes nothing',
        proves: 'ensureReachable answers noKeyPackage and nothing is '
            'published, with the same fixture carrying a key package as the '
            'control. Mutation-proven: dropping the mapping reddens it',
        clauses: ['mints nothing and says why'],
      );
      provenIn(
        'tests/at_functional_test/test/nskey_seeding_live_test.dart',
        'a client on the atSign\'s own credential mints nothing',
        proves: 'a real atServer lists primary with no key package, and a '
            'client on the demo keys reads that as noKeyPackage and publishes '
            'nothing',
        clauses: ['mints nothing and says why'],
      );
      provenIn(
        'packages/at_client/test/pq_signing_root_test.dart',
        'when it publishes, then its private reaches every other fully '
            'privileged enrollment carrying a verified key package',
        proves: 'the roster is read only once the root is published, the '
            'private reaches the fully privileged enrollment with a verified '
            'package, the refused one is named, the one with none is skipped '
            'silently, and one without `*` gets nothing. Mutation-proven for '
            'the privilege filter, the refused arm and the order',
        clauses: ['pushes its private, once the root is published'],
      );
      provenIn(
        'packages/at_client/test/pq_signing_root_test.dart',
        'when the push to one enrollment fails, then the mint succeeds and the '
            'others still receive it',
        proves: 'a failed push is logged, the mint returns its key, and the '
            'enrollment listed after the failure still receives it',
        clauses: ['pushes its private, once the root is published'],
      );
      provenIn(
        'packages/at_client/test/signing_root_pushed_to_approved_only_test.dart',
        'when it publishes, then only the approved enrollment receives its '
            'private',
        proves: 'of fully privileged enrollments listed approved, pending, '
            'denied, revoked and expired, only the approved one is pushed '
            'the root private',
        clauses: ['pushes its private, once the root is published'],
      );
      provenIn(
        'packages/at_client/test/nskey_filing_published_key_test.dart',
        'with nothing published under its kid, refuses a private whose seed '
            'derives another kid, and files the real one after it',
        proves: 'for the start-up bootstrap\'s, a key ring\'s and a '
            'rotation\'s filing, with nothing published, a seed that does not '
            'derive its kid is refused and the real one conveyed after it is '
            'filed, and a seed of one KEM under the other\'s kid is refused. '
            'Mutation-proven: accepting any seed with nothing published '
            'reddens every arm',
        clauses: ['derives the kid it was conveyed under'],
      );
      provenIn(
        'packages/at_client/test/nskey_filing_published_key_test.dart',
        'after a refused seed and the real one filed before the publish, an '
            'own write seals to the real public half',
        proves: 'heldPublic, which an own write seals to, answers the real '
            'generation\'s public half after a refused seed; with the refusal '
            'removed it answers nothing',
        clauses: ['derives the kid it was conveyed under'],
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
