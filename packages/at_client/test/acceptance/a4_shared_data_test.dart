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
      //       and read; alice's clients decapsulate the self-copy's CK — a
      //       SECOND CK in her own scope, since CKs are per recipient — with
      //       alice's nskey private. PQ end to end — no RSA on any path. An
      //       unauthorised @bob enrollment can neither fetch the ciphertext
      //       (server-gated) nor decrypt it.
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
        'alice shares with bob, and bob reads it with his own nskey private',
        proves:
            'bob opens the CK with HIS nskey private on an alice-owned record, and the same test asserts alice cannot decapsulate the CK she sealed to him',
          clauses: [
            'decapsulate bob\'s CK record with bob\'s nskey private and read',
          ]
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
        proves: 'against a namespace unique to the run — so @bob has genuinely '
            'never used it — the send fails with an exception naming both @bob '
            'and the namespace, the readiness query answers false BEFORE '
            'anything is composed, and the same query answers true for a '
            'namespace @bob has enabled, so the "no" carries information',
          clauses: [
            'pre-flight capability query** answers the same question before '
            'the user composes anything',
          ]
      );
      provenIn(
        'tests/at_functional_test/test/pq_legacy_interop_live_test.dart',
        'UC-B4.2 outbound · a PQ app on @bob reaches a legacy @alice throu',
        proves: 'the opted-in fallback arm against a real legacy recipient: '
            'with the flag set the share goes out under legacy rather than '
            'failing, and the record says so. Without the flag the same send '
            'refuses, which is the sibling arm and what stops this reading as '
            'the default',
        clauses: ['With the legacy fallback opted in (final 3.x only), the '
            'share proceeds under'],
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
        clauses: ['Once bob uses or authorises the namespace, his nskey is '
            'published'],
      );
    });

    test('UC-A4.3 · multi-enrollment both ends', () {
      // GIVEN alice (aE1, aE2) and bob (bE1, bE2) all PQ; bob has
      //       public:__nskey.app_1.my_apps@bob.
      // WHEN  alice2 shares with @bob.
      // THEN  all of bob's authorised enrollments read; all of alice's
      //       authorised enrollments read the self-copy; no authorised
      //       enrollment is left unable to decrypt.
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_multi_enrollment_test.dart',
        'UC-A4.3: every authorised enrollment of the recipient reads the share',
        proves: 'a second, genuinely distinct APKAM enrollment of @bob — its '
            'own enrollment id, APKAM keypair and client, asserted not '
            'identical to the first — reads the same record alice sealed '
            'once. The conveyance metadata read off the atServer names '
            'recipientKind nskey and the generation @bob advertised, which is '
            'the structural reason enrollment count is irrelevant: the seal is '
            'to (owner, namespace), not to a device',
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
        'UC-A4.4: providerId travels on the frame and bob decrypts by it',
        proves:
            'providerId is read off the notification frame bob\'s monitor delivered, and the value decrypts through the nskey route',
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
      provenIn(
        'packages/at_client/test/nskey_kem_selection_test.dart',
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
          ]
      );
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'two ML-KEM-1024 clients exchange the no-hybrid construction',
        proves: 'the whole chain under the second KEM — two clients configured '
            'for ml-kem-1024 mint, advertise, negotiate, seal and open at ver '
            '0x03. Paired with the negotiation arms in the same group, which '
            'run against an X-Wing recipient, it establishes that the '
            'RECIPIENT\'s advertised alg is what selects the KEM: the same '
            'sender code reaches a different construction purely by who it is '
            'sealing to.',
          clauses: [
            'symmetrically, a hybrid-configured `@bob` seals to an '
            'ML-KEM-1024 `@alice` at `ver 0x03`',
          ]
      );
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
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'the published advertisement emits its exact wire shape — raw literals',
        proves: 'that a generation advertises exactly one KEM: the emitted '
            'payload is pinned against hand-written literals and its keys '
            'list has length one. The list exists so a rotation can carry a '
            'second entry, so "one per generation" is a property of what a '
            'mint writes rather than of the format',
        clauses: ['each atSign advertises **one** KEM per generation, and '
            'rotation is the only moment that can change'],
      );
    });

    test('UC-A4.6 · the construction is negotiated from suites', () {
      // GIVEN two recipients holding the SAME X-Wing key, differing only in
      //       what their advertised record claims: one lists
      //       x-wing-rfc9180-v1, the other's record predates the suites field.
      // WHEN  alice1 seals to each.
      // THEN  the peer that lists RFC 9180 receives ver 0x02, and the peer
      //       that lists only the retired x-wing-hpke-v1 is REFUSED — there is
      //       no shared construction, and sealing this client's preference
      //       anyway would hand it a record it cannot open. (Until 0x01 was
      //       retired this arm received 0x01 instead; the negotiation is the
      //       same, only its outcome for a narrow peer changed.) The payload's
      //       declared suite and the envelope's version
      //       byte agree — the declared suite is what a receiver accepts on and
      //       the version byte is what it dispatches the KEM on, and a
      //       disagreement opens as an AEAD failure naming neither side. The
      //       candidates are narrowed to the chosen key's own KEM BEFORE the
      //       intersection, so a suite the key cannot decapsulate can never be
      //       selected. Unrecognised entries survive a parse, because the list
      //       is the holder's statement about itself. This is what moved the
      //       wire from 0x01 to 0x02 with no readers-upgrade-first migration,
      //       and then let 0x01 be dropped outright.
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
        clauses: ['the peer that lists RFC 9180 receives `pqSeal ver 0x02`; '
            'the peer that lists only'],
      );
      provenIn(
        'packages/at_chops/test/pq_hpke_test.dart',
        'a KEM that is not the version',
        proves: 'that the declared suite and the version byte cannot drift '
            'apart: a payload naming a KEM the version byte does not match is '
            'rejected at the seal layer. The agreement is asserted where it '
            'is decided, rather than inferred from a successful round trip',
        clauses: ['the payload\'s declared suite and the envelope\'s version '
            'byte **agree**'],
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a declared suites list is what the sender negotiates against',
        proves: 'the forward-compatibility rule at parse: a package declaring '
            'suites this build has never heard of keeps them rather than '
            'dropping them, so a newer holder is not silently narrowed to '
            'what this build understands. The fixture deliberately mixes an '
            'unknown name with a non-string entry',
        clauses: ['on parse, entries this build does not recognise are '
            '**kept**'],
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
        clauses: ['the candidate suites are narrowed to the **chosen key\'s '
            'own KEM** before the intersection'],
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
      provenIn(
        'packages/at_client/test/pairwise_secret_sharing_test.dart',
        'refuses rather than guessing when nothing is mutually supported',
        proves: 'the per-write arm — no overlap raises rather than falling '
            'back to the sender\'s own suite, and nothing is written. '
            '"pushSecretToNamespaceMembers skips it and still reaches the '
            'rest" holds the fan-out arm, where one unusable advertisement '
            'must not cost the rest of the roster theirs.',
          clauses: [
            'the operation is **refused** and nothing is written',
          ]
      );
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
        clauses: ['in a namespace fan-out a member with no mutually supported '
            'key is **skipped, not fatal**'],
      );
    });
  });
}
