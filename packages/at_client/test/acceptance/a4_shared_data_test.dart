/// A4 · E2EE across atSigns (shared data) + cross-atSign notification.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 5.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('A4 · shared data', () {
    test('UC-A4.1 · alice to bob, both PQ-native, bob has the namespace key',
        () {
      // GIVEN @alice, @bob pq-native; @bob published
      //       public:__nskey.app_1.my_apps@bob when he first used the namespace;
      //       bob1, bob2 hold its private; the app is at stage active on
      //       both sides.
      // WHEN  alice1 does put @bob:<k>.app_1.my_apps@alice (shouldEncrypt).
      // THEN  bob's clients decapsulate bob's CK record with bob's nskey private
      //       and read; which of bob's enrollments reads is immaterial, the
      //       reads differing by record-owner rather than by key. PQ end to
      //       end — no RSA on any path. Every authorised reader on both
      //       atSigns decrypts, and an unauthorised @bob enrollment can
      //       neither fetch the ciphertext (server-gated) nor decrypt it.
      provenIn('tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
          'alice shares with bob, and bob reads it with his own nskey private',
          proves:
              'bob opens the CK with HIS nskey private on an alice-owned record, and the same test asserts alice cannot decapsulate the CK she sealed to him',
          clauses: [
            'decapsulate bob\'s CK record with bob\'s nskey private and read',
          ]);
      provenIn(
        'packages/at_client/test/acceptance/cross_cutting_test.dart',
        'no RSA in any confidentiality path for a fully-PQ interaction',
        proves: 'the "PQ end to end" half, which is an absence and so cannot '
            'be shown by any single successful exchange: the invariant walks '
            'the confidentiality path of a fully-PQ interaction and finds no '
            'RSA on it. The live tests either side pin the positive routing — '
            'the value stamped at/symmetric/AES/GCM and the conveyance to the '
            'nskey — but neither can say nothing else was reached for',
        clauses: [
          'data values `providerId = at/symmetric/AES/GCM`, CK '
              'conveyances'
        ],
      );
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_multi_enrollment_test.dart',
        'UC-A4.3: whichever alice enrollment writes, every bob enrollment '
            'reads',
        proves: 'both halves of the last clause, in one test named for the '
            'row next door because it is that row\'s fixture the arm needs — '
            'two live enrollments of @bob, one of them scoped. AUTHORISED: '
            '@alice reads back what she wrote and both of @bob\'s '
            'enrollments read it, which is every authorised reader on both '
            'atSigns. UNAUTHORISED: @alice shares a second post-quantum '
            'record into a namespace @bob\'s second enrollment was never '
            'granted, and @bob\'s atServer refuses that enrollment the fetch '
            'as an authorization decision naming the verb, the enrollment id '
            'and the namespace — so it never holds the ciphertext, and "nor '
            'decrypt" is what follows rather than a second mechanism. The '
            'differential is tight: the SAME client reads the granted '
            'namespace and is refused the withheld one, so only the grant '
            'varies. Mutation-proven: making the fully privileged client the '
            'one refused reddens it, printing the decrypted value and the '
            'at/symmetric/AES/GCM routing — the refusal is a property of the '
            'reader, not of the record. ⚠️ The refusal cannot be shown by '
            '`llookup` on @bob\'s atServer: a record @alice shares lives on '
            'ALICE\'s atServer, so that verb answers "does not exist in '
            'keystore" whatever the grants are, which is an absent record '
            'dressed as a gate',
        clauses: [
          'cannot fetch the ciphertext (server-gated) nor decrypt',
        ],
      );
    });

    test('UC-A4.2 · alice to bob where bob has no namespace key, share fails',
        () {
      // GIVEN @alice, @bob pq-native; @bob has public:pq_signing_root@bob but
      //       NO public:__nskey.app_1.my_apps@bob — he has never used or
      //       authorised that namespace.
      // WHEN  alice1 shares @bob:<k>.app_1.my_apps@alice.
      // THEN  the share FAILS, with an exception naming @bob and the namespace
      //       so the app can say the recipient has not enabled it rather than
      //       report an encryption error. Bob's signing root is not a KEM
      //       target and cannot stand in. A pre-flight capability query answers
      //       the same question before the user composes anything. With the
      //       legacy fallback opted in (final 3.x only) the share proceeds
      //       under legacy — the invitation path, which ends at 4.x. Once bob
      //       uses or authorises the namespace his nskey is published and
      //       alice's next ensureCurrent picks it up by plookup.
      provenIn(
          'tests/at_end2end_test/test/pq/nskey_recipient_not_ready_test.dart',
          'UC-A4.2: a share to a recipient with no namespace key fails, naming',
          proves:
              'against a namespace unique to the run — so @bob has genuinely '
              'never used it — the send fails with an exception naming both @bob '
              'and the namespace, the readiness query answers false BEFORE '
              'anything is composed, and the same query answers true for a '
              'namespace @bob has enabled, so the "no" carries information',
          clauses: [
            'pre-flight capability query** answers the same question before '
                'the user composes anything',
          ]);
      provenIn(
        'tests/at_functional_test/test/pq_legacy_interop_live_test.dart',
        'UC-B4.2 outbound · a PQ app on @bob reaches a legacy @alice throu',
        proves: 'the opted-in fallback arm against a real legacy recipient: '
            'with the flag set the share goes out under legacy rather than '
            'failing, and the record says so. Without the flag the same send '
            'refuses, which is the sibling arm and what stops this reading as '
            'the default',
        clauses: [
          'With the legacy fallback opted in (final 3.x only), the '
              'share proceeds under'
        ],
      );
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
        'isReadyFor goes from false to true when bob mints',
        proves: 'the transition itself, across two atSigns: the namespace is '
            'run-unique and TOP-LEVEL on purpose, because a child namespace '
            'would resolve by walking up and the question would answer itself. '
            'isReadyFor is false, bob mints and publishes, and a FRESH alice '
            'sender then reads true — so the answer comes off the atServer '
            'rather than out of a cache alice already held',
        clauses: [
          'Once bob uses or authorises the namespace, his nskey is '
              'published'
        ],
      );
    });

    test('UC-A4.3 · multi-enrollment both ends', () {
      // GIVEN alice (aE1, aE2) and bob (bE1, bE2) all PQ; bob has
      //       public:__nskey.app_1.my_apps@bob.
      // WHEN  alice2 shares with @bob.
      // THEN  all of bob's authorised enrollments read the shared record,
      //       whichever of alice's enrollments wrote it; no authorised
      //       enrollment on the receiving side is left unable to decrypt.
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_multi_enrollment_test.dart',
        'UC-A4.3: whichever alice enrollment writes, every bob enrollment '
            'reads',
        proves: 'both sides vary against one record each. RECIPIENT: a second, '
            'genuinely distinct APKAM enrollment of @bob — its own enrollment '
            'id, APKAM keypair and client, asserted not identical to the '
            'first — reads the record alice sealed once, and the conveyance '
            'metadata read off the atServer names recipientKind nskey and the '
            'generation @bob advertised. SENDER: a second enrollment of '
            '@alice, with a store of its own, writes a second record that '
            'both of @bob\'s enrollments then read. It carries a DIFFERENT '
            'ckKid, which is what establishes that alice2 minted and conveyed '
            'its own content key rather than resuming the current-CK pointer '
            'alice1 left behind — mutating that write back onto alice1 '
            'reddens exactly that assertion. Together: readability is a '
            'property of (owner, namespace) on the receiving side and carries '
            'no sender identity a reader has to hold',
        clauses: [
          'whichever of alice\'s enrollments wrote it',
        ],
      );
    });

    test('UC-A4.4 · cross-atSign notification carrying an encrypted value', () {
      // GIVEN @alice, @bob pq-native; @bob published his nskey for the
      //       namespace; the app at stage active on both sides; bob1 on a
      //       monitor.
      // WHEN  alice1 notifies @bob with an encrypted value.
      // THEN  the value decrypts on every authorised bob enrollment with the
      //       same routing as a shared put; the notification scheme is the
      //       sending APP's decision exactly as a put's (toward a keyless bob
      //       it fails cold start or takes the explicit fallback — never a
      //       silent downgrade); offline-then-online bob still decrypts
      //       the queued notification; appMetadata is present on the frame;
      //       signal-only notifications are unaffected.
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_notify_test.dart',
        'UC-A4.4: providerId travels on the frame and every bob enrollment '
            'decrypts by it',
        proves: 'providerId is read off the notification frame each of @bob\'s '
            'monitors delivered, and the value decrypts through the nskey '
            'route on BOTH of his authorised enrollments — the second one a '
            'genuinely distinct APKAM enrollment with its own store, its own '
            'monitor connection and no nskey private of its own, so opening '
            'the value means the namespace private reached it by conveyance. '
            'Its monitor is gated on a notification actually arriving before '
            'anything is sent, because subscribe() returns before the socket '
            'has written `monitor:` and the monitor asks for no backlog. '
            'Mutation-proven: subscribing that enrollment with '
            'shouldDecrypt false reddens the value assertion with the '
            'ciphertext while the frame still arrives, which is the failure '
            'this clause guards against — delivered to both monitors, '
            'readable on one. OFFLINE: that enrollment\'s monitor socket is '
            'then closed and @alice sends again from her own client, on a '
            'different socket to a different atServer, so `delivered` means '
            '@bob\'s atServer took it for a listener that is not there. It '
            'comes back and the value still opens, on the key it already '
            'held. The outage itself is proven rather than assumed: the '
            'connection-down event is watched for before the close and gated '
            'on before anything is sent, because a notification handed to a '
            'live monitor and one replayed to a reconnecting one satisfy the '
            'same assertion — removing the close reddens that gate with an '
            'empty event list. ⚠️ `isNotifying` cannot serve as that gate and '
            'reads as though it can: it is a session flag cleared only by '
            'stopNotifications, and the reconnect loop reads it, so it stays '
            'true across the drop',
        clauses: [
          'The value decrypts on every authorised bob enrollment',
          'Offline-then-online bob still decrypts the queued notification',
        ],
      );
      provenIn(
        'tests/at_end2end_test/test/pq/pq_notify_fallback_test.dart',
        'UC-A4.4: the opted-in fallback governs a NOTIFY as well as a put',
        proves: 'the scheme-decision clause on both of its arms, against one '
            'client with one preference: with allowLegacyCryptoFallback set, '
            'a notification toward a recipient who has published nothing goes '
            'out stamped legacy rather than failing; with it unset, the same '
            'notification to the same recipient in the same namespace fails '
            'instead of downgrading. The control is the PUT path with the '
            'identical fixture, so the comparison is about the verb and '
            'nothing else. ⚠️ It was FALSE until 2026-08-27, not untested: '
            'the fallback lived in _putInternal and nowhere else, and both '
            'notify entry points called prepareWrite with no catch — so the '
            'same preference produced a legacy put and an undelivered '
            'notification, the exception telling the app to opt into the path '
            'it had already opted into. Mutation-proven: making the '
            'transformer refuse to fall back reddens this, quoting its own '
            'reason, with the put control green. ⚠️ It lives in its OWN file: notify '
            'folds a key outside the client app namespace into the key name and '
            'substitutes the client\'s, and AtClientManager caches a client per '
            '(atSign, enrollmentId) — so a second test in one file inherits the '
            'first test\'s namespace and every notify is silently redirected '
            'there',
        clauses: [
          'the write fails cold start or takes the explicit legacy fallback'
        ],
      );
      provenIn(
        'packages/at_client/test/acceptance/a3_self_data_test.dart',
        'UC-A3.4 · self notification carrying an encrypted value',
        proves: 'the signal-only half of this clause, which the live '
            'cross-atSign test does not exercise: a notification with no '
            'value leaves the decrypt count unchanged. The self scenario '
            'drives the same receive path, so the arm is established there '
            'rather than duplicated here',
        clauses: [
          'is present on the notification frame; signal-only '
              'notifications are unaffected'
        ],
      );
    });

    test('UC-A4.5 · the sender follows the recipient, not its own preference',
        () {
      // GIVEN @alice's deployment is configured for ml-kem-1024; @bob
      //       advertises an X-Wing key package and nskey.
      // WHEN  alice1 shares with @bob.
      // THEN  the seal is under X-WING, to bob's key. Alice's configuration
      //       decides what @alice is a RECIPIENT for and nothing about who she
      //       can send to. Symmetrically a hybrid-configured @bob seals to an
      //       ML-KEM-1024 @alice at ver 0x03; every build produces and opens
      //       both. Refusing would leave two atSigns unable to communicate
      //       while the peer's key stayed exactly as strong as it was — the
      //       peer's key is the peer's decision. The KEM itself is CONFIGURED
      //       per atSign and never negotiated per message, which is the
      //       downgrade surface SP 800-227 4.6.3 warns about; what is
      //       negotiated is the construction (UC-A4.6).
      // The clause itself, isolated: ONE sender, configured for ml-kem-1024
      // throughout, sealing to two destinations that differ only in what they
      // advertise. Added 2026-08-26 by the citation audit, which found that
      // the two citations below co-vary the sender's configuration with the
      // recipient's — both-X-Wing in one arm, both-ML-KEM in the other — so
      // neither isolates "the recipient decides", and a regression routing by
      // the sender's own algorithm would leave both green.
      provenIn('packages/at_client/test/nskey_kem_selection_test.dart',
          'the RECIPIENT advertisement decides the conveyance provider',
          proves: 'the differential the clause names, with the sender held '
              'fixed: the same ml-kem-1024-configured sender stamps the X-Wing '
              'conveyance provider for a recipient advertising X-Wing and the '
              'ML-KEM one for a recipient advertising ML-KEM, so the routing '
              'follows the advertisement and not the configuration. Mutating '
              'CkManager to pass the sender\'s own algorithm reddens it, and the '
              'failure is the production symptom — "@bob:myapp advertises a '
              'x-wing nskey, which at/nskey/MLKEM1024/AES/GCM cannot seal to", '
              'i.e. exactly the "refusing would protect nothing" outcome this '
              'row rejects.',
          clauses: [
            'refusing would protect nothing.** It would leave two atSigns '
                'unable to communicate',
            'the CK is sealed **under X-Wing**, to bob\'s key, at the '
                'strongest construction both sides list',
          ]);
      provenIn('packages/at_client/test/pairwise_secret_sharing_test.dart',
          'two ML-KEM-1024 clients exchange the no-hybrid construction',
          proves:
              'the whole chain under the second KEM — two clients configured '
              'for ml-kem-1024 mint, advertise, negotiate, seal and open at ver '
              '0x03. Paired with the negotiation arms in the same group, which '
              'run against an X-Wing recipient, it establishes that the '
              'RECIPIENT\'s advertised alg is what selects the KEM: the same '
              'sender code reaches a different construction purely by who it is '
              'sealing to.',
          clauses: [
            'symmetrically, a hybrid-configured `@bob` seals to an '
                'ML-KEM-1024 `@alice` under `ml-kem-1024-rfc9180-v1`',
          ]);
      provenIn(
        'packages/at_client/test/kem_selection_test.dart',
        'the two KEMs are not interchangeable',
        proves: 'why following the recipient is not a preference but a '
            'requirement — an envelope sealed under one KEM and opened with '
            'the other fails, so a sender that used its own configured KEM '
            'against a peer advertising the other would write a record the '
            'recipient can never open. "defaults to the hybrid" and "takes the '
            'no-hybrid option, and it resolves" pin the knob itself.',
      );
      // The four below carry the corrected clause: a holder may offer several
      // KEMs, and what removes the downgrade surface is that the offer is
      // signed and the order reading it is fixed. Until 2026-08-27 this clause
      // asserted the opposite — one KEM per generation — and rested the
      // SP 800-227 argument on it.
      provenIn(
        'packages/at_client/test/key_package_minting_test.dart',
        'a second algorithm is minted, filed and advertised beside the first',
        proves: 'the half the old clause denied: one enrollment advertising '
            'two KEMs at once. The package gains the newly configured '
            'algorithm\'s key without losing the one peers are already sealing '
            'to, which is what makes "more than one" a state the protocol '
            'reaches rather than a shape the format merely permits',
        clauses: ['a holder may advertise **more than one** KEM'],
      );
      // ⛔ A citation was WITHDRAWN here on 2026-08-27, and must not be
      // restored. It pinned the clause's old half — "an nskey generation
      // carries the FIRST of that list, because a mint writes one key" — to
      // nskey_minting_test.dart's raw-literal wire pin, whose keys list has
      // length one. The clause now says a generation carries a key for every
      // configured algorithm, so the same test proves the opposite of what the
      // catalogue states. That test is untouched and is the right place for it:
      // it goes red the day the mint stops taking the first algorithm, which is
      // exactly the signal wanted.
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a tampered advertisement is rejected',
        proves: 'why the offer cannot be edited on the way past: the sender '
            'verifies the APKAM signature before it reads a single key out of '
            'the advertisement, so an attacker can neither add a weak entry '
            'nor strip a strong one. This is what the security argument '
            'actually rests on, and nothing pinned it while the clause claimed '
            'the argument came from there being only one KEM to choose',
        clauses: ['the recipient\'s **APKAM-signed** advertised set'],
      );
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
        'the SENDER\'s order decides, not the recipient\'s',
        proves: 'the other leg: the selection order is the sender\'s own and '
            'the recipient cannot move it. Both lists hold both entries in '
            'OPPOSITE orders, so a walk driven by the wrong side returns the '
            'other answer — the two arms cannot collapse into each other, '
            'which is what makes this a proof about whose order it is rather '
            'than about which entry wins',
        clauses: ['its own fixed strongest-first `sealsToKeyAlgorithms`'],
      );
    });

    test('UC-A4.6 · the construction is negotiated from suites', () {
      provenIn('packages/at_client/test/nskey_resolver_test.dart',
          'a widened advertisement serves each sender the entry IT understands',
          proves: 'the sealer CHOOSES, as a differential over one '
              'advertisement: two senders differing only in '
              'sealsToKeyAlgorithms each resolve the entry they understand, so '
              'neither narrowing could be satisfied by a constant',
          clauses: ['record that choice']);
      provenIn('packages/at_client/test/nskey_kem_selection_test.dart',
          'either entry seals and opens, and each stamps its OWN kid',
          proves: 'that the choice is RECORDED and the opener simply uses it '
              '- the stamped kid is asserted BEFORE the round trip, because a '
              'wrong kid fetches the wrong private and would redden as a '
              'decapsulation error, proving nothing about the stamp',
          clauses: ['record that choice']);
      provenIn(
          'tests/at_functional_test/test/key_package_amendment_live_test.dart',
          'UC-A2.5 · a sender picks by its own order and stamps the matching ',
          proves: 'the same choice against a live atServer, over a recipient '
              'advertising both: two senders differing only in their own '
              'order pick differently and stamp what they picked',
          clauses: ['record that choice']);
      // GIVEN two recipients holding the SAME X-Wing key, differing only in
      //       what their advertised record claims: one lists
      //       x-wing-rfc9180-v1, the other's record predates the suites field.
      // WHEN  alice1 seals to each.
      // THEN  the peer that lists RFC 9180 receives ver 0x02, and the peer
      //       that lists only the retired x-wing-hpke-v1 is REFUSED — there is
      //       no shared construction, and sealing this client's preference
      //       anyway would hand it a record it cannot open. The payload's
      //       declared suite and the envelope's version
      //       byte agree — the declared suite is what a receiver accepts on and
      //       the version byte is what it dispatches the KEM on, and a
      //       disagreement opens as an AEAD failure naming neither side. The
      //       candidates are narrowed to the chosen key's own KEM BEFORE the
      //       intersection, so a suite the key cannot decapsulate can never be
      //       selected. Unrecognised entries survive a parse, because the list
      //       is the holder's statement about itself. This is what moved the
      //       wire to a new construction with no readers-upgrade-first
      //       migration.
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'negotiates RFC 9180 with a peer whose package says it opens it',
        proves: 'the upper arm. Its pair, "refuses a peer that only opens '
            'the retired construction", is asserted against the SAME X-Wing '
            'key, so the only thing differing between the two arms is what '
            'the package claims — two arms differing in key AND claim would '
            'prove nothing about the claim.',
      );
      provenIn(
        'tests/at_functional_test/test/secret_sharing_delivery_test.dart',
        'the negotiated construction is what actually reaches the atServer',
        proves: 'that the negotiated version is the version ON THE WIRE, which '
            'the unit arms structurally cannot show: their fixture backs local '
            'storage and the atServer with a single map. This reads the '
            'envelope back off a live atServer and looks at the bytes — the '
            'payload declares x-wing-rfc9180-v1 and the sealed blob\'s first '
            'byte is 0x02. Under the previous behaviour the assertion is '
            'false, so it is a differential against the change itself.',
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a package that names no suites is refused, not read as the oldest',
        proves: 'a package that states no suites is refused rather than '
            'answered for, and "a declared suites list is what the sender '
            'negotiates against" shows the stated list is what is negotiated '
            'against on parse — the field is the holder\'s statement about '
            'itself, so a newer holder may name a suite this build has never '
            'heard of.',
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'refuses a peer that only opens the retired construction',
        proves: 'the refusal half of the negotiation: a peer listing only the '
            'retired construction is turned away rather than sealed to at '
            'something it cannot open. Its pair asserts the accepting arm '
            'reads back as suite x-wing-rfc9180 at version 0x02, so the two '
            'together show the choice is made rather than defaulted',
        clauses: [
          'the peer that lists RFC 9180 receives `x-wing-rfc9180-v1`; '
              'the peer that lists only'
        ],
      );
      provenIn(
        'packages/at_chops/test/pq_hpke_test.dart',
        'a KEM that is not the version',
        proves: 'that the declared suite and the version byte cannot drift '
            'apart: a payload naming a KEM the version byte does not match is '
            'rejected at the seal layer. The agreement is asserted where it '
            'is decided, rather than inferred from a successful round trip',
        clauses: [
          'the payload\'s declared suite and the envelope\'s version '
              'byte **agree**'
        ],
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a declared suites list is what the sender negotiates against',
        proves: 'the forward-compatibility rule at parse: a package declaring '
            'suites this build has never heard of keeps them rather than '
            'dropping them, so a newer holder is not silently narrowed to '
            'what this build understands. The fixture deliberately mixes an '
            'unknown name with a non-string entry',
        clauses: [
          'on parse, entries this build does not recognise are '
              '**kept**'
        ],
      );
      provenIn(
        'tests/at_functional_test/test/key_package_amendment_live_test.dart',
        'UC-A2.5 · a sender picks by its own order and stamps the matching ',
        proves: 'the narrowing, as a differential over ONE recipient offering '
            'both KEMs: the only thing that varies is the sender\'s own '
            'preference order, and the two arms come back with different '
            'suites and different version bytes. A sender that intersected '
            'before narrowing to the chosen key\'s KEM could produce a suite '
            'that key cannot open, and both arms would still look like a '
            'success at the point of sending',
        clauses: [
          'the candidate suites are narrowed to the **chosen key\'s '
              'own KEM** before the intersection'
        ],
      );
    });

    test('UC-A4.7 · no mutually supported construction is a refusal', () {
      // GIVEN a recipient whose advertised record names only constructions this
      //       build does not implement (or no key it can encapsulate to).
      // WHEN  alice1 tries to seal to it.
      // THEN  the operation is REFUSED and nothing is written. Sealing under
      //       the sender's own preference would hand the recipient an envelope
      //       it cannot unwrap, and the failure would land on THEIR side as an
      //       opaque AEAD error with nothing to point at — every AEAD-level
      //       failure collapses to one outcome by design, so a guess is
      //       unattributable by construction. One level up, where the choice is
      //       per member rather than per write, the same rule reads as
      //       skipped-not-fatal: a member with no mutually supported key is
      //       skipped and every other member still receives its copy.
      provenIn('packages/at_client/test/pairwise_secret_sharing_test.dart',
          'refuses rather than guessing when nothing is mutually supported',
          proves: 'the per-write arm — no overlap raises rather than falling '
              'back to the sender\'s own suite, and nothing is written. '
              '"pushSecretToNamespaceMembers skips it and still reaches the '
              'rest" holds the fan-out arm, where one unusable advertisement '
              'must not cost the rest of the roster theirs.',
          clauses: [
            'the operation is **refused** and nothing is written',
          ]);
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'no overlap is null rather than a guess',
        proves: 'the decision underneath both arms: bestSuiteFor returns '
            'nothing rather than a default, so every caller has to handle the '
            'no-overlap case explicitly instead of inheriting a silent '
            'fallback. "an id this build does not implement is null, not a '
            'guess" in kem_selection_test.dart is the same rule one layer '
            'down, at the algorithm id.',
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'pushSecretToNamespaceMembers skips it and still reaches the rest',
        proves: 'that one unreachable member does not take the fan-out down: '
            'a peer whose only key names an algorithm this build cannot '
            'encapsulate to is skipped, and the remaining members still '
            'receive. The rest-still-reached half is what distinguishes a '
            'skip from a swallowed failure',
        clauses: [
          'in a namespace fan-out a member with no mutually supported '
              'key is **skipped, not fatal**'
        ],
      );
    });
  });
}
