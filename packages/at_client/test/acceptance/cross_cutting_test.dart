/// Cross-cutting acceptance — invariants testable against EVERY use case.
///
/// These are not a cluster in the A/B sequence; they are properties every
/// scenario above must preserve. Treat a failure here as a design violation,
/// not a scenario bug.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 13.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import 'blockers.dart';
import 'proven_elsewhere.dart';

void main() {
  group('cross-cutting invariants', () {
    test('reads are universal', () async {
      // A client decrypts anything ever written to it (all providers retained);
      // upgrading only ever ADDS read-capability.
      //
      // The mechanism is that `legacy` is a *built-in* fallback rather than an
      // entry in `providers` — so it survives a config that lists only the PQ
      // set, and no upgrade can drop it by omission. That is asserted here as a
      // differential: the only thing that varies between the two arms is the
      // provider id stamped on the record, so a green result cannot come from
      // both arms failing the same way.
      final client = MockAtClient();
      // The 4.x shape — PQ registered AND the write default. The most
      // aggressive config a client will ever hold, and legacy reads must still
      // route under it.
      client.getPreferences().crypto =
          CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());
      final runtime = CryptoRuntime(client);

      AtKey stamped(String? providerId) => AtKey()
        ..key = 'historic'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()
          ..appMetadata =
              providerId == null ? null : AppMetadata(providerId: providerId));

      // Arm 1: a legacy record. Routing must find the built-in provider. It
      // then fails inside that provider on this bare mock, which is a
      // *different* failure — the point is only that resolution succeeded.
      await expectLater(
          () => runtime.decryptForGet(stamped(legacyCryptoProviderId), 'c'),
          throwsA(isNot(isA<CryptoProviderNotRegistered>())),
          reason: 'a PQ-configured client must still ROUTE a legacy record; if '
              'this is CryptoProviderNotRegistered then upgrading silently '
              'dropped the ability to read everything written before it');

      // Same, for a record predating appMetadata entirely.
      await expectLater(() => runtime.decryptForGet(stamped(null), 'c'),
          throwsA(isNot(isA<CryptoProviderNotRegistered>())),
          reason: 'an unstamped record is legacy by definition and must route '
              'the same way');

      // Arm 2 — the control. An id genuinely absent resolves to nothing, so
      // arm 1 above is a real resolution rather than a router that never
      // rejects anything.
      await expectLater(
          () => runtime.decryptForGet(stamped('at/some/scheme/from/2030'), 'c'),
          throwsA(isA<CryptoProviderNotRegistered>()),
          reason: 'control: an unregistered id must fail loudly, or arm 1 '
              'proves nothing about resolution');

      // And the failure names what to add, because "reads are universal" is
      // only true if a client meeting a newer scheme can be told which one.
      await expectLater(
          () => runtime.decryptForGet(stamped('at/some/scheme/from/2030'), 'c'),
          throwsA(predicate((e) =>
              '$e'.contains('at/some/scheme/from/2030') &&
              '$e'.contains(legacyCryptoProviderId) &&
              '$e'.contains(nskeyCryptoProviderId))),
          reason: 'the error must name the missing id AND the registered set, '
              'so an operator can see what this client is short of');

      // The additive half, stated directly: the PQ config resolves the PQ ids,
      // and resolving them did not cost it the legacy one above.
      final config = CryptoConfig.forClient(client);
      expect(config.lookup(nskeyCryptoProviderId), isNotNull);
      expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    });

    test('writes are gated by reader readiness', () {
      // A value/notification is only written in a scheme EVERY required reader
      // supports; otherwise legacy (3.x), or REFUSED under
      // disallowLegacyEncryption = true.
      fail('not implemented');
    }, skip: r1);

    test('appMetadata.providerId is authoritative on keys and frames',
        () async {
      // Present on BOTH stored keys and notification frames, with the no-ns
      // shapes: at/nskey/XWING/AES/GCM ->
      //   {providerId, recipientKind, ckKid, nskeyKid};
      // at/symmetric/AES/GCM -> {providerId, ckKid, iv}. A providerId names
      // every algorithm a reader needs code for, so a scheme change is
      // rollable rather than a flag day.
      //
      // "and frames" is not the whole story: it must also survive every hop
      // that WRITES a record to the atServer. The sync push silently dropped
      // appMetadata — a hand-rolled metadata serializer in SyncServiceImpl that
      // had fallen behind Metadata.toAtProtocolFragment — so every cross-atSign
      // read fell back to legacy, for every provider, not just the PQ ones
      // (decisions.md section 17). Assert the round-trip through sync, not just
      // the in-memory stamp: an out-of-order or missing field in that fragment
      // is dropped without an error.
      const owner = '@alice';
      const namespace = 'app_1.my_apps';
      final context = CryptoContext(atClient: MockAtClient());

      final pair = await XWingKeyPair.generate();
      final cache = ContentKeyCache();
      final ring = InMemoryNskeyKeyRing();
      final nskeyKid = ring.seedKeypair(owner, namespace,
          publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
      final nskey = NskeyProvider(keyRing: ring, cache: cache);
      final data = SymmetricAesGcmProvider(cache: cache);

      AtKey key(String name) => AtKey()
        ..key = name
        ..namespace = namespace
        ..sharedBy = owner
        ..metadata = Metadata();

      final ck =
          ContentKey(Uint8List.fromList(base64Decode(AESKey.generate(32).key)));

      // The conveyance: at/nskey -> {providerId, recipientKind, ckKid,
      // nskeyKid}. Read back off the key the provider stamped, not off a
      // literal — a shape that drifts must fail here.
      final conveyance = key('${ck.ckKid}.__ck');
      await nskey.encrypt(context, conveyance, ck.toBase64());
      cache.putAsCurrent(owner, namespace, ck, nskeyKid);
      final conveyanceMeta = conveyance.metadata.appMetadata!;
      expect(conveyanceMeta.providerId, nskeyCryptoProviderId);
      expect(conveyanceMeta.additional, containsPair('ckKid', ck.ckKid));
      expect(conveyanceMeta.additional, containsPair('nskeyKid', nskeyKid));
      expect(conveyanceMeta.additional?['recipientKind'], isNotNull,
          reason: 'the reader needs to know what kind of key this was sealed '
              'to before it can pick one to open it with');

      // The value: at/symmetric/AES/GCM -> {providerId, ckKid, iv}. No sealed
      // key inline — it CITES a conveyance.
      final value = key('treaty');
      await data.encrypt(context, value, 'the treaty text');
      final valueMeta = value.metadata.appMetadata!;
      expect(valueMeta.providerId, symmetricAesGcmCryptoProviderId);
      expect(valueMeta.additional, containsPair('ckKid', ck.ckKid));
      expect(valueMeta.additional?['iv'], isNotNull,
          reason: 'AES-GCM is unsafe under IV reuse, so the IV is per-record '
              'and has to travel with the record');

      // The round-trip that actually broke: appMetadata must survive the
      // serializer on the way OUT to the atServer. A field the fragment drops
      // is dropped silently, and every reader then falls back to legacy.
      for (final stamped in [conveyance, value]) {
        final fragment = stamped.metadata.toAtProtocolFragment();
        // appMetadata rides the fragment base64-encoded, so decode it rather
        // than substring-matching: a match on the raw fragment would pass on
        // an accidental collision and fail on a legal re-encoding, and neither
        // outcome says anything about what the reader will get.
        final encoded =
            RegExp(r'appMetadata:([A-Za-z0-9+/=]+)').firstMatch(fragment);
        expect(encoded, isNotNull,
            reason: 'appMetadata must reach the wire at all — when the sync '
                'push dropped it, every cross-atSign read fell back to legacy '
                'for every provider, with no error anywhere');
        final decoded = jsonDecode(utf8.decode(base64Decode(encoded![1]!)))
            as Map<String, dynamic>;

        expect(decoded['providerId'], stamped.metadata.appMetadata!.providerId,
            reason: 'the provider id is what routes the read; a record that '
                'arrives without it is opened with the wrong scheme');
        expect(decoded['ckKid'], ck.ckKid,
            reason: 'and the additional entries travel with it, or the reader '
                'routes to the right provider and still cannot find the key');
      }

      // "and frames" is the other half: one serializer serves both the stored
      // key and the notification frame. The regression was a SECOND,
      // hand-rolled serializer that fell behind this one, so the guard worth
      // having is that neither call site has grown its own again.
      final lib = Directory('${repoRoot().path}/packages/at_client/lib/src');
      for (final path in const [
        'service/sync_service_impl.dart',
        'service/notification_service_impl.dart',
      ]) {
        expect(File('${lib.path}/$path').readAsStringSync(),
            contains('toAtProtocolFragment'),
            reason: '$path must serialize metadata through the shared '
                'fragment builder; a private one beside it is how appMetadata '
                'silently stopped reaching the atServer once already');
      }
    });

    test('no RSA in any confidentiality path for a fully-PQ interaction',
        () async {
      // Auth, enrollment conveyance, self, shared, and notification paths.
      //
      // Read precisely: this row is about **confidentiality**, and auth has no
      // confidentiality component to have. A prove-possession handshake needs a
      // signature only — the per-connection challenge supplies freshness and
      // TLS supplies the channel — so the PQ move there is a signature swap,
      // not a KEM. RSA still being used to SIGN a PKAM challenge is therefore
      // not an RSA confidentiality path, and swapping it is RF-2b's PQ-APKAM
      // mint rather than this row's business. What auth does guarantee is
      // covered by the record-authoritative row above.
      //
      // That leaves the paths that genuinely carry secrets, and the assertion
      // is that the provider set the SDK assembles for them contains nothing
      // RSA at all.
      final config = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());

      final nskey = config.lookup(nskeyCryptoProviderId);
      final data = config.lookup(symmetricAesGcmCryptoProviderId);
      expect(nskey, isA<NskeyProvider>(),
          reason: 'the content key is conveyed under X-Wing — a KEM, where '
              'there is a secret to transport');
      expect(data, isA<SymmetricAesGcmProvider>(),
          reason: 'and the value itself under AES-256-GCM');

      // The ids are the wire contract, and each names every algorithm a reader
      // needs code for. Neither may name RSA, on any casing.
      for (final id in [
        nskeyCryptoProviderId,
        symmetricAesGcmCryptoProviderId
      ]) {
        expect(id.toLowerCase(), isNot(contains('rsa')),
            reason: 'a provider id is what a reader routes on; RSA appearing '
                'in one would mean records are being written to an RSA path');
      }
      expect(config.defaultProviderId, symmetricAesGcmCryptoProviderId,
          reason: 'and a fully-PQ interaction WRITES that path — otherwise the '
              'set is merely registered and the interaction is not PQ at all');

      // Self, shared and notification all route through those two providers —
      // proven live rather than asserted here, since a unit test cannot see
      // which providers a real write actually reached.
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_e2e_test.dart',
        'a self value round-trips through the nskey data path',
        proves: 'self data is sealed and opened through X-Wing + AES-GCM on a '
            'live atServer, with no legacy provider involved',
      );
      provenIn(
        'tests/at_end2end_test/test/nskey_cross_atsign_test.dart',
        'alice shares with bob, and bob reads it with his own nskey private',
        proves: 'the shared path is the same two providers across atSigns',
      );
      provenIn(
        'tests/at_end2end_test/test/concurrent_notify_test.dart',
        'UC-A4.4: providerId travels on the frame and bob decrypts by it',
        proves: 'and the notification path routes by the same provider id',
      );

      // The enrollment conveyance — the one place a secret really is
      // transported during onboarding — carries no RSA wrap in pq mode.
      provenIn(
        'tests/at_functional_test/test/enrollment_pq_key_exchange_e2e_test.dart',
        'a pq enrollment reaches the atServer with no RSA-wrapped key',
        proves: 'the enrol request carries no RSA-wrapped apkamSymmetricKey; '
            'the approver mints it and seals it to the advertised X-Wing key '
            'package instead',
      );
    });

    test('ML-DSA APKAM auth is record-authoritative', () {
      // PQ auth verifies against the enrollment record's single apkamPublicKey
      // using the RECORD signingAlgo — _getSigningAlgoType reads the record,
      // NEVER the client-supplied wire value.
      provenIn(
        'tests/at_functional_test/test/pkam_record_authoritative_test.dart',
        'the wire signingAlgo is a claim, and the record decides',
        proves: 'a pkam: command signed with the enrollment\'s real RSA key '
            'but CLAIMING mldsa65 on the wire still authenticates, so the '
            'atServer chose its verifier from the record and not from the '
            'caller. The truthful claim is the control, and the built command '
            'is asserted to actually carry the claim so the two arms differ',
      );
    });

    test('pq_signing_root is create-once; the published nskey is not', () {
      // A second public:pq_signing_root@<atSign> create is rejected, never an
      // overwrite — it is the root and never rotates, so two enrollments
      // minting two roots would be unrecoverable. public:__nskey.<ns>@owner is
      // mutable BY DESIGN,
      // because nskey-keypair rotation has to overwrite it; two of the owner's
      // enrollments are kept apart by the short-ttl immutable lock
      // _nskeylock.<ns>@owner, and substitution is prevented by the APKAM
      // signature over the advertised envelope, not by the write mode.
      provenIn(
        'tests/at_functional_test/test/pq_signing_root_create_once_test.dart',
        'a second signing-root create is refused, and changes nothing',
        proves: 'the atServer refuses the second create WITH the immutability '
            'error, the stored value is byte-identical afterwards, and a '
            'mutable public key written twice by the same client is the '
            'control that the refusal is about immutability',
      );
      provenIn(
        'tests/at_functional_test/test/pq_signing_root_create_once_test.dart',
        'the published nskey is mutable, because rotation depends on it',
        proves: 'a second mintAndPublish on one namespace produces a new '
            'nskeyKid and the advertisement resolves to it — the opposite '
            'requirement, on the same atSign, so "immutable" landing on the '
            'wrong record of the two would fail here',
      );
    });

    test('a published nskey is fetchable but not enumerable', () {
      // public:__nskey.<ns>@owner resolves on an exact plookup, cross-atSign, and
      // appears in NO scan — with or without showhidden, authenticated or not.
      // A guaranteed protocol property (_apsk already relies on it); this is a
      // regression guard against a server change retiring it.
      //
      // Two citations because the claim has two halves and no single test
      // holds both: enumerability is an atServer property provable against one
      // atSign, while "cross-atSign" needs a second one to do the fetching.
      provenIn(
        'tests/at_functional_test/test/underscore_public_key_hiding_test.dart',
        'a public:__ key syncs, is served by plookup, and is not enumerable',
        proves: 'the exact plookup returns it while neither the owner\'s '
            'showhidden scan nor a genuinely unauthenticated outsider\'s can '
            'enumerate it — with an ordinary public key and a second hidden '
            'key as controls, so the absence is a real absence',
      );
      provenIn(
        'tests/at_end2end_test/test/nskey_cross_atsign_test.dart',
        'alice shares with bob, and bob reads it with his own nskey private',
        proves: 'alice resolves bob\'s published nskey across atSigns before '
            'she can seal to it, which is the cross-atSign fetch half',
      );
    });

    test('advertised recipient keys are signed and verified', () {
      // Every advertised encapsulation key — the per-enrollment key package and
      // the published nskey public half — is an APKAM-signed envelope verified
      // against the enrollment's _apsk THE SAME WAY same-atSign and
      // cross-atSign, BEFORE encapsulating to it. A tampered, unsigned, or
      // wrong-signer advertised key is REJECTED. The atServer keeps every
      // approved enrollment's _apsk present (fetchable without a client
      // publish) and write-restricted (a cross-enrollment overwrite is
      // refused). The signing root is not on this list: it is a verification
      // key, so nothing is ever encapsulated to it.
      //
      // Both halves hold today at unit level — published_nskey_key_ring_test
      // and key_package_registration_test cover the rejections — and the nskey
      // half is driven on the live wire by nskey_cross_atsign_test. What this
      // still owed was the atServer side (_apsk present without a client
      // publish, a cross-enrollment overwrite refused) plus a live
      // enroll:listns. All three needed two genuine APKAM enrollments, since
      // the interesting case is one enrollment reaching for another's record.
      provenIn(
        'tests/at_functional_test/test/apsk_server_side_test.dart',
        'the atServer publishes _apsk itself, and refuses a cross-enrollment',
        proves: 'the victim\'s _apsk is fetchable without that client ever '
            'publishing it, an attacker enrollment\'s overwrite is refused as '
            'an authorization decision naming both enrollments, the record is '
            'byte-identical afterwards, and the same connection CAN write its '
            'own _apsk — so the restriction is per-enrollment rather than a '
            'blanket ban',
      );
      provenIn(
        'tests/at_functional_test/test/apsk_server_side_test.dart',
        'enroll:listns answers an APKAM connection with the namespace members',
        proves: 'the live enumeration the substrate\'s push and pull both '
            'depend on returns the enrollments authorised for the namespace',
      );
      provenIn(
        'tests/at_end2end_test/test/nskey_cross_atsign_test.dart',
        'alice shares with bob, and bob reads it with his own nskey private',
        proves: 'and the nskey half of the same claim on the live wire — an '
            'advertised encapsulation key verified against its signer before '
            'anything is sealed to it, cross-atSign',
      );
    });

    test('performance is measured, not assumed', () {
      // PKAM-auth and put/get latency deltas vs the legacy RSA/AES path are
      // measured on one reference low-end device by a bench harness landed WITH
      // B-1. The harness is the durable artefact, re-run on every later
      // key-shape change. The ceiling is pinned when the harness lands — a
      // measured budget, not a guessed number.
      //
      // What this asserts is the *instrument and the record*, not a threshold.
      // A ceiling pinned to one machine's numbers would fail on somebody
      // else's laptop for no defensible reason, and a benchmark that fails for
      // an indefensible reason gets deleted. So: the harness must exist and
      // still expose its measurement primitives, and the budget must be
      // written down with the basis it was measured on.
      final harness = File(
          '${repoRoot().path}/packages/at_client/benchmark/crypto_bench.dart');
      expect(harness.existsSync(), isTrue,
          reason: 'the harness IS the deliverable for this row — without it '
              'every performance claim about the PQ path is a guess again');

      final harnessSource = harness.readAsStringSync();
      for (final primitive in const ['prewarm', 'measure', 'median', 'p90']) {
        expect(harnessSource, contains(primitive),
            reason: 'the harness must keep reporting a distribution. A mean '
                'over a total hides exactly the variance ML-DSA signing has, '
                'and prewarm is what stopped a 256 B encrypt measuring slower '
                'than a 4096 B one');
      }

      final decisions = File('${repoRoot().path}/docs/projects/pq/decisions.md')
          .readAsStringSync();
      expect(decisions, contains('The PQ performance budget, measured'),
          reason: 'a harness nobody has run pins nothing; the measured budget '
              'has to be recorded where the next reader will find it');
      for (final basis in const [
        'per record',
        'per (owner, namespace)',
        'per authentication',
      ]) {
        expect(decisions, contains(basis),
            reason: 'the budget must state which basis each figure is on. '
                'X-Wing seal is per-namespace and RSA wrap is per-recipient — '
                'quoting the 19x ratio between them without saying so is the '
                'single most misleading thing available in this data');
      }
    });
  });
}
