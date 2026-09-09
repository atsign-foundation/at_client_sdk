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
import 'manifest.dart';
import 'proven_elsewhere.dart';

void main() {
  group('cross-cutting invariants', () {
    test('reads are universal', () async {
      // A client decrypts anything ever written to it under any scheme its
      // stage configures, and upgrading only ever ADDS read-capability.
      //
      // NOTE: `legacy` is a built-in fallback rather than an entry in
      // `providers`, so it survives a config that lists only the PQ set and no
      // upgrade can drop it by omission.
      final client = MockAtClient();
      client.getPreferences().crypto =
          CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());
      final runtime = CryptoRuntime(client);

      AtKey stamped(String? providerId) => AtKey()
        ..key = 'historic'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()
          ..appMetadata =
              providerId == null ? null : AppMetadata(providerId: providerId));

      // The assertion is only that resolution succeeded: the call then fails
      // inside the provider on this bare mock, which is a different failure.
      await expectLater(
          () => runtime.decryptForGet(stamped(legacyCryptoProviderId), 'c'),
          throwsA(isNot(isA<CryptoProviderNotRegistered>())),
          reason: 'a PQ-configured client must still ROUTE a legacy record; if '
              'this is CryptoProviderNotRegistered then upgrading silently '
              'dropped the ability to read everything written before it');

      await expectLater(() => runtime.decryptForGet(stamped(null), 'c'),
          throwsA(isNot(isA<CryptoProviderNotRegistered>())),
          reason: 'an unstamped record is legacy by definition and must route '
              'the same way');

      await expectLater(
          () => runtime.decryptForGet(stamped('at/some/scheme/from/2030'), 'c'),
          throwsA(isA<CryptoProviderNotRegistered>()),
          reason: 'control: an unregistered id must fail loudly, or arm 1 '
              'proves nothing about resolution');

      await expectLater(
          () => runtime.decryptForGet(stamped('at/some/scheme/from/2030'), 'c'),
          throwsA(predicate((e) =>
              '$e'.contains('at/some/scheme/from/2030') &&
              '$e'.contains(legacyCryptoProviderId) &&
              '$e'.contains(nskeyCryptoProviderId))),
          reason: 'the error must name the missing id AND the registered set, '
              'so an operator can see what this client is short of');

      final config = CryptoConfig.forClient(client);
      expect(config.lookup(nskeyCryptoProviderId), isNotNull);
      expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    });

    test('no silent scheme substitution, in either direction', () async {
      // The SDK never chooses post-quantum behind the app's back — writing PQ
      // is the app's release decision — and never downgrades behind its back
      // either: an explicit provider id is honoured or thrown, never
      // substituted, and under disallowLegacyEncryption a legacy-only path is
      // REFUSED, never quietly written legacy. The cold-start refusal's own
      // rows are UC-A3.3/UC-A4.2.
      const bob = '@bob';
      const namespace = 'app_1.my_apps';

      AtKey toBob() => AtKey()
        ..key = 'treaty'
        ..namespace = namespace
        ..sharedBy = '@alice'
        ..sharedWith = bob;

      final capability = MockAtClient();
      capability.getPreferences()
        ..namespace = namespace
        ..crypto = CryptoConfig.readsNskeyWritesLegacy(
            keyRing: InMemoryNskeyKeyRing());
      expect(CryptoRuntime.providerIdFor(capability, null, atKey: toBob()),
          legacyCryptoProviderId,
          reason: 'this client resolves both PQ providers — the ladder, not a '
              'missing capability, is what keeps its writes legacy');

      final active = MockAtClient();
      active.getPreferences()
        ..namespace = namespace
        ..crypto = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());
      expect(CryptoRuntime.providerIdFor(active, null, atKey: toBob()),
          symmetricAesGcmCryptoProviderId);

      // An explicit request is honoured or thrown, never substituted: the
      // nskey path cannot serve a namespace-less key, and quietly writing
      // legacy instead is how data gets believed PQ when it is not.
      final internalKey = AtKey()
        ..key = 'shared_key.bob'
        ..sharedBy = '@alice'
        ..metadata = (Metadata()..namespaceAware = false);
      expect(
          () => CryptoRuntime.providerIdFor(active, nskeyCryptoProviderId,
              atKey: internalKey),
          throwsA(isA<AtEncryptionException>()));

      final strict = StrictMockAtClient();
      strict.getPreferences()
        ..namespace = namespace
        ..crypto = const CryptoConfig.legacy();
      expect(() => CryptoRuntime.providerIdFor(strict, null, atKey: toBob()),
          throwsA(isA<LegacyEncryptionRefusedException>()));
    });

    test('appMetadata.providerId is authoritative on keys and frames',
        () async {
      // Present on BOTH stored keys and notification frames, with the no-ns
      // shapes: at/nskey/XWING/AES/GCM ->
      //   {providerId, recipientKind, ckKid, nskeyKid};
      // at/symmetric/AES/GCM -> {providerId, ckKid, iv}. A providerId names
      // every algorithm a reader needs code for, so a scheme change is
      // rollable rather than a flag day.
      //
      // NOTE: appMetadata must also survive every hop that WRITES a record to
      // the atServer, so the round-trip through the metadata fragment is
      // asserted rather than the in-memory stamp alone — a field the fragment
      // drops is dropped without an error, and every reader then falls back to
      // legacy.
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
      // nskeyKid}.
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

      for (final stamped in [conveyance, value]) {
        final fragment = stamped.metadata.toAtProtocolFragment();
        // appMetadata rides the fragment base64-encoded, so decode it rather
        // than substring-matching the raw fragment.
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

      // One serializer serves both the stored key and the notification frame;
      // that neither call site has a private serializer is a property of the
      // source, asserted by `architecture_guard_test.dart`.
    });

    test('no RSA in any confidentiality path for a fully-PQ interaction',
        () async {
      // Auth, enrollment conveyance, self, shared, and notification paths.
      //
      // This row is about confidentiality, and auth has none to have: a
      // prove-possession handshake needs a signature only — the per-connection
      // challenge supplies freshness and TLS supplies the channel — so RSA
      // signing a PKAM challenge is not an RSA confidentiality path. The
      // assertion is that the provider set the SDK assembles for the paths
      // that do carry secrets contains nothing RSA at all.
      final config = CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing());

      final nskey = config.lookup(nskeyCryptoProviderId);
      final data = config.lookup(symmetricAesGcmCryptoProviderId);
      expect(nskey, isA<NskeyProvider>(),
          reason: 'the content key is conveyed under X-Wing — a KEM, where '
              'there is a secret to transport');
      expect(data, isA<SymmetricAesGcmProvider>(),
          reason: 'and the value itself under AES-256-GCM');

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

      // Self, shared and notification route through those two providers,
      // proven live because a unit test cannot see which providers a real
      // write reached.
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a self value round-trips through the nskey data path',
        proves: 'self data is sealed and opened through X-Wing + AES-GCM on a '
            'live atServer, with no legacy provider involved',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
        'alice shares with bob, and bob reads it with his own nskey private',
        proves: 'the shared path is the same two providers across atSigns',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_notify_test.dart',
        'UC-A4.4: providerId travels on the frame and every bob enrollment '
            'decrypts by it',
        proves: 'and the notification path routes by the same provider id',
      );

      // The enrollment conveyance — the one place a secret really is
      // transported during onboarding — carries no RSA wrap in pq mode.
      provenIn(
        'tests/at_functional_test/test/enrollment_pq_key_exchange_live_test.dart',
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

    test('neither key record is immutable; the lock that mints them is', () {
      // public:pq_signing_root@<atSign> and public:__nskey.<ns>@owner are both
      // mutable, and for the same reason: rotation has to overwrite the
      // advertisement, and the root's rotation is a successor entry beside a
      // retired predecessor. Two of the owner's enrollments are kept apart by
      // a short-ttl IMMUTABLE lock key — _rootlock@owner and
      // _nskeylock.<ns>@owner — and substitution is prevented by the APKAM
      // signature over the advertised envelope, not by the write mode.
      provenIn(
        'tests/at_functional_test/test/pq_signing_root_mint_lock_test.dart',
        'the metadata the signing root is written with is mutable on the ',
        proves: 'the metadata pqSigningRootKey produces is written twice to a '
            'live atServer and the second write lands, and what the atServer '
            'stored carries no immutable flag. Proved on a SCRATCH record '
            'rather than the root: a probe that landed would replace the '
            'atSign\'s root for the rest of the run, which it did once',
      );
      provenIn(
        'tests/at_functional_test/test/pq_signing_root_mint_lock_test.dart',
        'a second signing-root mint lock create is refused',
        proves: 'the atServer refuses the second _rootlock create WITH the '
            'immutability error — the interlock the record used to carry — '
            'and the same take succeeds once the lock is released, which is '
            'the control that the refusal is about immutability',
      );
      provenIn(
        'tests/at_functional_test/test/pq_signing_root_mint_lock_test.dart',
        'the published nskey is mutable, because rotation depends on it',
        proves: 'a second mintAndPublish on one namespace produces a new '
            'nskeyKid and the advertisement resolves to it — the same '
            'requirement as the root, on the same atSign, so "immutable" '
            'landing back on either record would fail here',
      );
    });

    test('a second signing root is representable, publishable and verifiable',
        () {
      // The root's ROTATABILITY, not the rotation: a keyfile and a record each
      // carrying two root entries — one active, one retired — with a link
      // signed under the RETIRED one still verifying, and no rotation
      // machinery anywhere. Once that holds, rotation is a later operation
      // over a structure that already works.
      provenIn(
        'packages/at_client/test/pq_signing_chain_test.dart',
        'D1 boundary: a keyfile and a record both carrying two root entries',
        proves: 'one scenario drives both halves through the real APIs: the '
            'successor arrives over the ordinary filing path and lands in its '
            'own slot beside the retired predecessor, signing selects the '
            'active root and stamps its kid, and the link signed earlier '
            'under the retired one still verifies through both verifiers. '
            'Isolated by mutation — filing the successor over its '
            "predecessor's slot reddens this row and nothing else",
      );
    });

    test('a published nskey is fetchable but not enumerable', () {
      // public:__nskey.<ns>@owner resolves on an exact plookup, cross-atSign, and
      // appears in NO scan — with or without showhidden, authenticated or not.
      // A guaranteed protocol property (_apsk already relies on it); this is a
      // regression guard against a server change retiring it.
      provenIn(
        'tests/at_functional_test/test/underscore_public_key_hiding_test.dart',
        'a public:__ key syncs, is served by plookup, and is not enumerable',
        proves: 'the exact plookup returns it while neither the owner\'s '
            'showhidden scan nor a genuinely unauthenticated outsider\'s can '
            'enumerate it — with an ordinary public key and a second hidden '
            'key as controls, so the absence is a real absence',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
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
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'an advertisement signed by another atSign is rejected',
        proves: 'the wrong-signer shape on the nskey half: the payload is a '
            'genuine signed advertisement and the _apsk served for its owner '
            'is somebody else\'s, which is what a substituted key looks like '
            'from the sender\'s side',
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'a tampered advertisement is rejected',
        proves: 'the tampered shape: the signature stays valid over the '
            'original body and only the advertised key is swapped, so a '
            'verifier that checked the envelope without binding it to the '
            'key inside would pass this',
      );
      provenIn(
        'packages/at_client/test/published_nskey_key_ring_test.dart',
        'an unsigned advertisement is rejected, not accepted bare',
        proves: 'the unsigned shape, which is the one a tolerant reader gets '
            'wrong: accepting a bare key leaves the sealing target only as '
            'trustworthy as the server that served it',
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a key package signed by another enrollment is not sealed to',
        proves: 'the same wrong-signer shape on the key-package half — '
            'enroll-b\'s record carrying a package enroll-d signed, which '
            'accepted would hand enroll-d every secret meant for enroll-b',
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'a tampered key package is not sealed to',
        proves: 'and the tampered shape there, signature intact over the '
            'original body with the advertised key swapped',
      );
      provenIn(
        'packages/at_client/test/key_package_registration_test.dart',
        'an unsigned key package is not sealed to',
        proves: 'and the bare one, refused rather than read — the member '
            'comes back with a null key package instead of an unverified one',
      );

      // The atServer side is the half no unit test can reach: the _apsk
      // present without a client publish, the cross-enrollment overwrite
      // refused, and a live enroll:listns.
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
        'tests/at_end2end_test/test/pq/nskey_cross_atsign_test.dart',
        'alice shares with bob, and bob reads it with his own nskey private',
        proves: 'and the nskey half of the same claim on the live wire — an '
            'advertised encapsulation key verified against its signer before '
            'anything is sealed to it, cross-atSign',
      );
    });

    test('performance is measured, not assumed',
        timeout: const Timeout(Duration(minutes: 2)), () {
      // PKAM-auth and put/get latency deltas vs the legacy RSA/AES path come
      // from a bench harness run on one reference low-end device. This asserts
      // the instrument and the record, not a threshold: a ceiling pinned to
      // one machine's numbers would fail on somebody else's laptop for no
      // defensible reason. So the harness must exist and still expose its
      // measurement primitives, and the budget must be written down with the
      // basis it was taken on.
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

      // NOTE: the instrument has to BUILD, not merely contain the right
      // identifiers — the routine local `dart analyze lib test` never looks in
      // `benchmark/`, so nothing else catches a harness that stopped
      // compiling.
      final analyze = Process.runSync(
        Platform.resolvedExecutable,
        const ['analyze', 'benchmark'],
        workingDirectory: '${repoRoot().path}/packages/at_client',
      );
      expect(analyze.exitCode, 0,
          reason: 'the harness must BUILD, not merely contain the right '
              'identifiers — a bench nobody can run pins nothing. '
              '`dart analyze benchmark` said:\n${analyze.stdout}');

      final decisions =
          File('${repoRoot().path}/docs/projects/pq/detail/decisions.md')
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
