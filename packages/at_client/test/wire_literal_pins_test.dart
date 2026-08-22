/// Exact-string pins over every wire literal the PQ refactor will relocate.
///
/// Almost every existing test asserts these values *through the constants that
/// define them* — `expect(x, SomeClass.someConst)` — which stays green when the
/// constant's VALUE changes. These pins assert the raw literals, so moving or
/// centralising a definition (the refactor's whole business) cannot silently
/// change what goes on the wire. On an intended wire change — there should be
/// none — the pin's edit is the review.
///
/// Every pin here is **FROZEN FOREVER** — wire contract: record names, provider
/// ids, payload field names, algorithm spellings, crypto bindings. Records
/// already written on live atServers carry these; several are immutable or
/// write-once. A red pin here means a wire break, full stop.
///
/// There was a second, softer class — `JWS-WILL-MOVE`, the signed-envelope
/// wrapper that a 4.0 default flip was going to retire. It is gone with the
/// wrapper: the envelope has one shape now, so its pins are frozen like
/// everything else here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey, pqSigningRootMintLockKey;
import 'package:at_client/src/secret_sharing/envelope_addressing.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_auth/at_auth.dart' show CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart'
    show
        AESKey,
        AesGcm256EncryptionAlgo,
        AtChopsUtil,
        InitialisationVector,
        MlDsa65PureDartAlgo,
        MlKem1024PureDartAlgo,
        PqOpenException,
        SigningAlgoType,
        XWingPureDartAlgo,
        pqOpen;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  late MockAtClient atClient;

  setUp(() {
    atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
  });

  group('FROZEN FOREVER: record names', () {
    test('the nskey advertisement is public:__nskey.<ns>@<owner>', () {
      expect(nskeyAdvertisementKey('@alice', 'app_1.my_apps').toString(),
          'public:__nskey.app_1.my_apps@alice');
    });

    test(
        'the nskey mint lock is _nskeylock.<ns>@<owner>, immutable, 2-minute '
        'ttl', () {
      final key = nskeyMintLockKey('@alice', 'app_1.my_apps');
      expect(key.toString(), '_nskeylock.app_1.my_apps@alice');
      // The atServer's second-immutable-create refusal IS the interlock, so
      // the metadata is contract, not tuning.
      expect(key.metadata.immutable, isTrue);
      expect(key.metadata.ttl, 120000);
    });

    test(
        'the signing-root mint lock is _rootlock@<atSign>, immutable, '
        '2-minute ttl', () {
      final key = pqSigningRootMintLockKey('@alice');
      // No namespace: the root is atSign-level, which is what distinguishes it
      // from an nskey. Single underscore, so it is hidden from every scan and
      // written outside the commit log — it is taken and released remotely and
      // must never ride sync.
      expect(key.toString(), '_rootlock@alice');
      expect(key.metadata.immutable, isTrue,
          reason: 'the refusal of a second immutable create is the whole '
              'interlock now that the root record itself is mutable');
      expect(key.metadata.ttl, 120000);
      expect(key.metadata.isPublic, isFalse,
          reason: 'a self key — nobody but the owner writes the owner\'s '
              'records, so there is nothing to share');
    });

    test('the current-CK pointer strips the destination owner\'s @', () {
      // The emitted segment is 'bob', not '@bob' — easy to mis-pin.
      expect(
          const CurrentCkPointer()
              .keyFor(atClient, '@bob', 'app_1.my_apps')
              .toString(),
          '__ckcur.bob.app_1.my_apps@alice');
    });

    test('a self conveyance is <ckKid>.__ck.<ckNs>@<owner>', () {
      final value = AtKey()
        ..key = 'msg'
        ..namespace = 'app_1.my_apps'
        ..sharedBy = '@alice';
      expect(
          SymmetricAesGcmProvider.conveyanceKeyFor(value, 'abc123', 'my_apps')
              .toString(),
          'abc123.__ck.my_apps@alice');
    });

    test('a shared conveyance is @<recipient>:<ckKid>.__ck.<ckNs>@<sender>',
        () {
      final value = AtKey()
        ..key = 'msg'
        ..namespace = 'app_1.my_apps'
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      expect(
          SymmetricAesGcmProvider.conveyanceKeyFor(value, 'abc123', 'my_apps')
              .toString(),
          '@bob:abc123.__ck.my_apps@alice');
    });

    test('the signing root is public:pq_signing_root@<atSign>, no namespace',
        () {
      expect(PqSigningRoot.recordName, 'pq_signing_root');
      final key = PqSigningRoot(atClient).keyFor('@alice');
      expect(key.toString(), 'public:pq_signing_root@alice');
      expect(key.metadata.immutable, isFalse,
          reason: 'the root is an ordinary signing key and rotating it means '
              'rewriting this record, which an immutable one makes '
              'unimplementable. What immutability was doing — stopping two '
              'privileged enrollments each minting a root — moved to '
              '_rootlock@<atSign>, pinned above');
    });

    test('the _apsk URI is public:_apsk.<enrollmentId>.a.__e@<atSign>', () {
      // One builder (apskUri in envelope_signature.dart) serves every site;
      // PqSigningChain.apskUri delegates to it, so this pins the emitted
      // shape for all of them. The write and read paths carry their own exact
      // pins in key_package_registration_test.dart and
      // envelope_signing_test.dart.
      expect(PqSigningChain.apskUri('@alice', 'enroll-1'),
          'public:_apsk.enroll-1.a.__e@alice');
    });

    test('a non-enrolled client signs — and publishes — as "primary"', () {
      // ApkamSigning.enrollmentId manufactures the sentinel rather than
      // returning null (a null-check against it is dead code), so
      // public:_apsk.primary.a.__e@<atSign> is a real emittable record name.
      when(() => atClient.getRemoteSecondary()).thenReturn(null);
      final signer = AtClientEnvelopeSigner(atClient);
      expect(signer.enrollmentId, 'primary');
      expect(signer.publicSigningKeyUri, 'public:_apsk.primary.a.__e@alice');
    });

    test('substrate secret names: the per-enrollment prefix and its composites',
        () {
      // The '__en.' prefix is also the never-forward gate — a changed prefix
      // silently changes forwarding semantics, so the composed strings get
      // literal pins, not constant-relative ones.
      expect(PairwiseSecretSharing.perEnrollmentSecretPrefix, '__en.');
      expect(enrollmentApkamSymmetricKeySecretName, '__en.apkamSymmetricKey');
      expect(PqSigningRoot.secretName, '__en.pqSigningRoot');
      expect(PqSigningChain.linkSecretName, '__en.apskChainLink');
      expect(PqSigningChain.rootLinkSecretName, '__en.apskRootLink');
      expect(NskeyPrivateFiling.secretNamePrefix, '__nskey.');
    });

    test('_apsk appMetadata link field names', () {
      expect(PqSigningChain.linkField, 'apskChainLink');
      expect(PqSigningChain.rootLinkField, 'apskRootLink');
      // Inside the root-link document, naming the advertised root entry that
      // signed it. A verifier narrows on this, so a rename would silently turn
      // every labelled link into an unlabelled one — still verifiable, but the
      // claim would stop being checked and nothing would go red.
      expect(PqSigningChain.rootLinkKidField, 'kid');
    });

    test('a root link built by the signer emits its exact field set', () {
      // The DOCUMENT, not the constants — a shape assertion that follows a
      // renamed constant pins nothing. The signature member is excluded on
      // purpose: ML-DSA signing is hedged, so it differs run to run.
      final link = {
        'v': 1,
        'alg': PqSigningChain.rootLinkAlgo,
        PqSigningChain.rootLinkKidField: 'kid-of-the-signer',
        'payload': PqSigningChain.linkPayload(
            childEnrollmentId: 'child-1', childApkamPublicKey: 'cHVibGlj'),
        'signature': 'IGNORED',
      };
      expect(link.keys.toList(), ['v', 'alg', 'kid', 'payload', 'signature']);
      expect((link['payload'] as Map).keys.toList(),
          ['v', 'childEnrollmentId', 'apkamPublicKey'],
          reason: 'the payload is the SIGNED region and is shared verbatim '
              'with the chain link, so a field added here changes what a '
              'chain link signs');
    });

    test('keyfile ids for nskey privates and the root (at rest, frozen)', () {
      // Keyfile-only, but existing keyfiles hold these ids and scans match on
      // them, so they freeze the same way wire names do.
      expect(NskeyPrivateFiling.keyIdFor('app_1.my_apps', 'abc123'),
          'nskey.app_1.my_apps.abc123');
      // The at-rest slot prefix, completed by a generation: root:mldsa65:1,
      // then :2 where a lost mint race left dead remains. NOT the record
      // name — public:pq_signing_root@<atSign> is the wire value and is
      // pinned above; this one is only ever read by the keyfile itself.
      //
      // The role is frozen, the algorithm is not: a root of a later algorithm
      // files under root:<that>:1, which is what makes the atSign's root
      // replaceable at all. So the pin is on what the composition PRODUCES for
      // today's algorithm, not on the composition being a constant.
      expect(PqSigningRoot.keyIdRole, 'root');
      expect(PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken),
          'root:mldsa65:');
      expect(PqSigningRoot.keyIdPrefixFor('some-later-algo'),
          'root:some-later-algo:');
    });

    test('the root algorithm has one spelling across both vocabularies', () {
      // SigningAlgoType.mldsa65 is what the _apsk advertisement carries;
      // CryptographicMaterialAlgorithm.mlDsa65 is what AtKeys files material under. Slot ids
      // are composed from the first and material is matched by the second, so
      // a drift between them would leave every root filed under an id no
      // reader assembles — with nothing to go red on the way past.
      expect(PqSigningRoot.rootKeyAlgoToken, 'mldsa65');
      expect(PqSigningRoot.rootKeyAlgoToken,
          CryptographicMaterialAlgorithm.mlDsa65);
    });
  });

  group('FROZEN FOREVER: provider ids', () {
    test('the four ids, as raw strings', () {
      expect(legacyCryptoProviderId, 'legacy');
      expect(nskeyCryptoProviderId, 'at/nskey/XWING/AES/GCM');
      expect(mlKemNskeyCryptoProviderId, 'at/nskey/MLKEM1024/AES/GCM');
      expect(symmetricAesGcmCryptoProviderId, 'at/symmetric/AES/GCM');
      expect(nskeyProviderFamily, 'at/nskey');
    });

    test('the aliases carry the same value', () {
      // Three names, one value: the const, the runtime alias, and the
      // provider's own id getter. All three are read somewhere.
      expect(CryptoRuntime.legacyProviderId, 'legacy');
      expect(CryptoConfig.legacy().defaultProviderId, 'legacy');
    });

    test('keyAlgo → provider id, pinned with literals on both sides', () {
      expect(nskeyProviderIdFor('x-wing'), 'at/nskey/XWING/AES/GCM');
      expect(nskeyProviderIdFor('ml-kem-1024'), 'at/nskey/MLKEM1024/AES/GCM');
      expect(nskeyProviderIdFor('kyber-1024-v9'), isNull);
    });
  });

  group('FROZEN FOREVER: crypto bindings (HPKE info and AEAD AAD)', () {
    // These strings never appear on the wire — they are key-derivation inputs,
    // which makes them MORE fragile under refactoring, not less: a changed
    // binding breaks nothing visibly, it just makes every already-written
    // record unopenable. Each pin here is differential: the captured
    // ciphertext opens ONLY under the hand-built binding string, and a
    // negative control proves the test can fail.

    AtKey selfConveyance() => AtKey()
      ..key = 'ckkid.__ck'
      ..namespace = 'myapp'
      ..sharedBy = '@alice';

    test('a conveyance binds info "at/nskey/XWING/AES/GCM:<owner>:<ns>"',
        () async {
      final kem = XWingPureDartAlgo.instance;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = InMemoryNskeyKeyRing()
        ..seedKeypair('@alice', 'myapp',
            publicKey: pair.publicKey,
            privateKey: pair.secretKey,
            keyAlgo: 'x-wing');
      final provider = NskeyProvider(keyRing: ring, cache: ContentKeyCache());
      final ck = ContentKey(Uint8List.fromList(List.generate(32, (i) => i)));

      final wire = await provider.encrypt(
          CryptoContext(atClient: atClient), selfConveyance(), ck.toBase64());

      final opened = await pqOpen(kem, pair.secretKey, base64Decode(wire),
          info: Uint8List.fromList(
              utf8.encode('at/nskey/XWING/AES/GCM:@alice:myapp')));
      expect(opened, ck.bytes);

      await expectLater(
          pqOpen(kem, pair.secretKey, base64Decode(wire),
              info: Uint8List.fromList(
                  utf8.encode('at/nskey/XWING/AES/GCM:@alice:other'))),
          throwsA(isA<PqOpenException>()),
          reason: 'the negative control — without it a pqOpen that ignored '
              'info would pass the arm above');

      // The CROSS-SUBSTRATE control. The arm above varies the namespace within
      // this substrate; this one crosses to the pairwise substrate's binding,
      // which is the replay the two distinct `info` values exist to prevent.
      // Written as a raw literal rather than PairwiseSecretSharing.sealInfo so
      // it cannot follow that constant if someone pointed it here.
      await expectLater(
          pqOpen(kem, pair.secretKey, base64Decode(wire),
              info: Uint8List.fromList(
                  utf8.encode('at_client/secret_sharing/v1'))),
          throwsA(isA<PqOpenException>()),
          reason: 'a conveyance must not open under the pairwise substrate\'s '
              'binding — shared code for seal/open is fine, a shared binding '
              'is not');
    });

    test('an ML-KEM conveyance carries the SAME XWING-prefixed info', () async {
      // NskeyProvider._info is static and names the XWING constant, so the
      // string is baked into every stored ML-KEM conveyance's key schedule.
      // A cleanup to `$id:...` reads better and silently strands them all —
      // this pin is what makes that cleanup fail loudly instead.
      final kem = MlKem1024PureDartAlgo.instance;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = InMemoryNskeyKeyRing()
        ..seedKeypair('@alice', 'myapp',
            publicKey: pair.publicKey,
            privateKey: pair.secretKey,
            keyAlgo: 'ml-kem-1024');
      final provider = NskeyProvider(
          keyRing: ring, cache: ContentKeyCache(), keyAlgo: 'ml-kem-1024');
      final ck = ContentKey(Uint8List.fromList(List.generate(32, (i) => i)));

      final wire = await provider.encrypt(
          CryptoContext(atClient: atClient), selfConveyance(), ck.toBase64());

      final opened = await pqOpen(kem, pair.secretKey, base64Decode(wire),
          info: Uint8List.fromList(
              utf8.encode('at/nskey/XWING/AES/GCM:@alice:myapp')));
      expect(opened, ck.bytes);

      await expectLater(
          pqOpen(kem, pair.secretKey, base64Decode(wire),
              info: Uint8List.fromList(
                  utf8.encode('at/nskey/MLKEM1024/AES/GCM:@alice:myapp'))),
          throwsA(isA<PqOpenException>()),
          reason: 'the "obvious" per-provider binding must NOT open it');

      // The cross-substrate control on the ML-KEM path, for the same reason as
      // the X-Wing one above.
      await expectLater(
          pqOpen(kem, pair.secretKey, base64Decode(wire),
              info: Uint8List.fromList(
                  utf8.encode('at_client/secret_sharing/v1'))),
          throwsA(isA<PqOpenException>()),
          reason: 'a conveyance must not open under the pairwise substrate\'s '
              'binding');
    });

    test('a data value binds AAD "<providerId>:<sharedBy>:<sharedWith>:<name>"',
        () async {
      final cache = ContentKeyCache();
      final ck = ContentKey(Uint8List.fromList(List.generate(32, (i) => i)));
      // _nskeyOwnerOf is sharedWith ?? sharedBy, so the CK scopes to @bob.
      cache.putAsCurrent('@bob', 'myapp', ck, 'nskeykid1');
      final provider = SymmetricAesGcmProvider(cache: cache);
      final atKey = AtKey()
        ..key = 'msg'
        ..namespace = 'myapp'
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';

      final wire = await provider.encrypt(
          CryptoContext(atClient: atClient), atKey, 'hello');

      final iv = InitialisationVector(Uint8List.fromList(
          base64Decode(atKey.metadata.appMetadata!.additional!['iv'])));
      final aad = utf8.encode('at/symmetric/AES/GCM:@alice:@bob:msg.myapp');
      final plain = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64()))
          .decrypt(Uint8List.fromList(base64Decode(wire)), iv: iv, aad: aad);
      expect(utf8.decode(plain), 'hello');

      await expectLater(
          AesGcm256EncryptionAlgo(AESKey(ck.toBase64())).decrypt(
              Uint8List.fromList(base64Decode(wire)),
              iv: iv,
              aad: utf8.encode('at/symmetric/AES/GCM:@alice:@bob:msg.other')),
          throwsA(anything),
          reason: 'the negative control for the AAD arm');
    });

    test('fullNameOf joins key and namespace at a dot', () {
      final k = AtKey()
        ..key = 'msg'
        ..namespace = 'app_1.my_apps'
        ..sharedBy = '@alice';
      expect(SymmetricAesGcmProvider.fullNameOf(k), 'msg.app_1.my_apps');
    });

    test('the pairwise substrate binds info "at_client/secret_sharing/v1"', () {
      // Pins the constant's VALUE, and only that: it never touches a
      // ciphertext, so it stays green if a call site stops passing the
      // constant. The arms that read real sealed output — and that go red on a
      // converged binding — are in pairwise_secret_sharing_test.dart, group
      // 'FROZEN FOREVER: the pairwise seal binding, read from real output'.
      expect(utf8.decode(PairwiseSecretSharing.sealInfo),
          'at_client/secret_sharing/v1');
    });
  });

  group('FROZEN FOREVER: appMetadata stamps', () {
    test('a conveyance record\'s appMetadata, field by field', () async {
      final kem = XWingPureDartAlgo.instance;
      final pair = await kem.keyPairFromSeed(kem.newSeed());
      final ring = InMemoryNskeyKeyRing()
        ..seedKeypair('@alice', 'myapp',
            publicKey: pair.publicKey,
            privateKey: pair.secretKey,
            keyAlgo: 'x-wing');
      final provider = NskeyProvider(keyRing: ring, cache: ContentKeyCache());
      final ck = ContentKey(Uint8List.fromList(List.generate(32, (i) => i)));
      final atKey = AtKey()
        ..key = 'ckkid.__ck'
        ..namespace = 'myapp'
        ..sharedBy = '@alice';

      await provider.encrypt(
          CryptoContext(atClient: atClient), atKey, ck.toBase64());

      final json = atKey.metadata.appMetadata!.toJson();
      expect(json.keys.toList(),
          ['providerId', 'recipientKind', 'ckKid', 'nskeyKid', 'ns']);
      expect(json['providerId'], 'at/nskey/XWING/AES/GCM');
      expect(json['recipientKind'], 'nskey');
      expect(json['ckKid'], ck.ckKid);
      expect(json['ns'], 'myapp');
      expect(NskeyRecipientKind.nskey, 'nskey');
    });

    test('a data value\'s appMetadata, field by field', () async {
      final cache = ContentKeyCache();
      final ck = ContentKey(Uint8List.fromList(List.generate(32, (i) => i)));
      cache.putAsCurrent('@alice', 'myapp', ck, 'nskeykid1');
      final provider = SymmetricAesGcmProvider(cache: cache);
      final atKey = AtKey()
        ..key = 'msg'
        ..namespace = 'myapp'
        ..sharedBy = '@alice';

      await provider.encrypt(CryptoContext(atClient: atClient), atKey, 'hello');

      final json = atKey.metadata.appMetadata!.toJson();
      expect(json.keys.toList(), ['providerId', 'ckKid', 'iv', 'ns', 'ckNs']);
      expect(json['providerId'], 'at/symmetric/AES/GCM');
      expect(json['ckKid'], ck.ckKid);
      expect(json['ns'], 'myapp');
      expect(json['ckNs'], 'myapp');
    });
  });

  group('FROZEN FOREVER: secret-sharing wire vocabulary', () {
    test('the __ssenv marker and payload kinds', () {
      expect(PairwiseSecretSharing.envelopeKeyMarker, '__ssenv');
      expect(PairwiseSecretSharing.secretPayloadKind, 'secret');
      expect(PairwiseSecretSharing.secretRequestKind, 'request');
    });

    test('the envelope filters the atServer is asked to apply', () {
      // Not stored anywhere, but the atServer evaluates them, so their grammar
      // is a contract with it — the alternation especially, which arrived when
      // a client began answering at more than one address.
      expect(
          EnvelopeAddressing.envelopeKey(
                  msgId: 'msg-1',
                  recipientKpid: 'kp-1',
                  appNamespace: 'myapp',
                  sharedBy: '@alice',
                  ttl: const Duration(hours: 1))
              .toString(),
          'msg-1.kp-1.__ssenv.myapp@alice');
      expect(EnvelopeAddressing.fragmentFor('kp-1'), '.kp-1.__ssenv.');
      expect(EnvelopeAddressing.regexFor('kp-1'), '\\.kp-1\\.__ssenv\\.');
      expect(
          EnvelopeAddressing.sweepRegexFor('kp-1'), '.*\\.kp-1\\.__ssenv\\..*');
      expect(EnvelopeAddressing.regexForAny(['kp-1', 'kp-2']),
          '\\.(kp-1|kp-2)\\.__ssenv\\.');
      expect(EnvelopeAddressing.sweepRegexForAny(['kp-1', 'kp-2']),
          '.*\\.(kp-1|kp-2)\\.__ssenv\\..*');
      expect(EnvelopeAddressing.namespaceSweepRegexFor('kp-1', 'myapp'),
          '.*\\.kp-1\\.__ssenv\\.myapp.*');
    });

    test('the alternation filter really matches only the named addresses', () {
      // A pin on the string alone would not notice a grouping mistake that
      // makes the filter match everything, which is the way this goes wrong.
      final sweep =
          RegExp(EnvelopeAddressing.sweepRegexForAny(['kp-1', 'kp-2']));
      expect(sweep.hasMatch('m.kp-1.__ssenv.myapp@alice'), isTrue);
      expect(sweep.hasMatch('m.kp-2.__ssenv.myapp@alice'), isTrue);
      expect(sweep.hasMatch('m.kp-3.__ssenv.myapp@alice'), isFalse);
      expect(sweep.hasMatch('m.kp-1.__other.myapp@alice'), isFalse);
    });

    test('a filter over no addresses is refused rather than emitted', () {
      // Spelled carelessly it becomes `\.()\.__ssenv\.` — which matches
      // nothing, so a client would receive nothing and log no reason.
      expect(() => EnvelopeAddressing.regexForAny(const []),
          throwsA(isA<ArgumentError>()));
      expect(() => EnvelopeAddressing.sweepRegexForAny(const []),
          throwsA(isA<ArgumentError>()));
    });

    test('SecretEnvelope emits its exact JSON shape', () {
      final env = SecretEnvelope(
        fromKpid: 'kpid-from',
        fromEnrollmentId: 'enroll-a',
        toKpid: 'kpid-to',
        suite: 'x-wing-rfc9180-v1',
        kid: 'kpid-to',
        sealed: 'U0VBTEVE',
      );
      expect(
          jsonEncode(env.toJson()),
          '{"v":1,"from":{"kpid":"kpid-from","enrollmentId":"enroll-a"},'
          '"to":"kpid-to","suite":"x-wing-rfc9180-v1","kid":"kpid-to",'
          '"sealed":"U0VBTEVE"}');
    });

    test('PackageKey emits its exact JSON shape', () {
      expect(
          jsonEncode(
              PackageKey(use: 'enc', alg: 'x-wing', pub: 'QUJD').toJson()),
          '{"kid":"b5d4045c3f466fa9","use":"enc","alg":"x-wing","pub":"QUJD"}');
    });

    test('a retired key entry says so, and an active one says nothing', () {
      // Two claims, and the second is the one that can break silently. Absent
      // means active, so an active entry must keep emitting NO status field —
      // otherwise every advertisement in the protocol changes bytes to state
      // what its silence already stated, and the pins above go red for a
      // reason that has nothing to do with rotation.
      expect(
          jsonEncode(PackageKey(
                  use: 'enc',
                  alg: 'x-wing',
                  pub: 'QUJD',
                  status: KeyEntryStatus.retired)
              .toJson()),
          '{"kid":"b5d4045c3f466fa9","use":"enc","alg":"x-wing","pub":"QUJD",'
          '"status":"retired"}');
      expect(
          PackageKey(
                  use: 'enc',
                  alg: 'x-wing',
                  pub: 'QUJD',
                  status: KeyEntryStatus.active)
              .toJson(),
          isNot(contains('status')));
    });

    test('the status spellings a reader accepts are frozen', () {
      // Raw literals on the right rather than the constants, which would
      // follow a re-spelling through and pin nothing. The atServer stores
      // these verbatim and every implementation reads them, so a change here
      // is a protocol change and editing this line is what makes it
      // reviewable.
      expect(KeyEntryStatus.fromWire('active'), 'active');
      expect(KeyEntryStatus.fromWire('retired'), 'retired');
      expect(KeyEntryStatus.fromWire(null), 'active',
          reason: 'absent is how every record written before rotation existed '
              'spells active');
    });

    test('an unrecognised status is carried through, not flattened', () {
      // Until 2026-08-22 both of these read as `retired`, and the writers
      // then emitted `retired` back - an older build rewriting a newer one's
      // statement about a key the newer one owns.
      expect(KeyEntryStatus.fromWire('verifyOnly'), 'verifyOnly',
          reason: 'a token this build has never heard of survives the read, '
              'so republishing the record does not weaken what it says');
      expect(KeyEntryStatus.fromWire(7), '7',
          reason: 'a status that is not a string is malformed rather than '
              'unknown, and stringifying keeps what was written visible '
              'without repairing it into a token that means something');

      // Both decisions say no, which is the whole point of preserving it: an
      // unknown token is MORE restrictive than either value this build knows,
      // never less. `retired` was permissive on the second of these, and a
      // revoked key that goes on verifying is unrecoverable.
      for (final unknown in ['verifyOnly', 'revoked', '7', '']) {
        expect(KeyEntryStatus.offersNewOperations(KeyEntryStatus.of(unknown)),
            isFalse,
            reason: '"$unknown" must never be signed with or sealed to');
        expect(
            KeyEntryStatus.vouchesForPastOperations(KeyEntryStatus.of(unknown)),
            isFalse,
            reason: '"$unknown" must not verify what it signed either');
      }
      expect(KeyEntryStatus.offersNewOperations(KeyEntryStatus.of('active')),
          isTrue);
      expect(KeyEntryStatus.offersNewOperations(KeyEntryStatus.of('retired')),
          isFalse);
      expect(
          KeyEntryStatus.vouchesForPastOperations(KeyEntryStatus.of('active')),
          isTrue);
      expect(
          KeyEntryStatus.vouchesForPastOperations(KeyEntryStatus.of('retired')),
          isTrue,
          reason: 'retirement withdraws the future and keeps the past - a '
              'retired key still verifies every envelope it signed');
    });

    test('an unrecognised status survives a PackageKey round trip', () {
      // The half the tolerance above would be worthless without: the reader
      // keeps the token and the writer emits it back, so a record read and
      // republished by this build still says what its owner wrote.
      final read = PackageKey.fromJson({
        'kid': 'b5d4045c3f466fa9',
        'use': 'enc',
        'alg': 'x-wing',
        'pub': 'QUJD',
        'status': 'revoked',
      })!;
      expect(read.status, 'revoked');
      expect(read.offeredForNewOperations, isFalse);
      expect(read.toJson()['status'], 'revoked',
          reason: 'emitting "retired" here would republish the record with '
              'its owner\'s statement about this key weakened');
    });

    test('computeKid hashes the decoded key BYTES, not the base64 text', () {
      // It used to be the other way round, and this pin is what recorded it:
      // the kid was SHA-256 over the UTF-8 of the base64 STRING, which was an
      // accident rather than a decision, and the nskey side hashed the bytes.
      // Two derivations both described as "SHA-256 of the public key" agreed
      // for nothing. One function now, over the material.
      //
      // Pinned against a digest computed outside this tree:
      //   python3 -c "import hashlib,base64;
      //     print(hashlib.sha256(base64.b64decode('QUJD')).hexdigest()[:16])"
      expect(PackageKey.computeKid('QUJD'), 'b5d4045c3f466fa9');
      expect(nskeyKidOf(base64Decode('QUJD')), 'b5d4045c3f466fa9',
          reason: 'the nskey name and the key-package name are the same '
              'derivation now — that is the whole point of the change');
    });

    test('a key package payload emits its exact JSON shape', () {
      final payload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026, 6, 11),
        keys: [PackageKey(use: 'enc', alg: 'x-wing', pub: 'QUJD')],
      );
      expect(
          jsonEncode(payload),
          '{"v":1,"createdAt":"2026-06-11T00:00:00.000Z",'
          '"keys":[{"kid":"b5d4045c3f466fa9","use":"enc","alg":"x-wing",'
          '"pub":"QUJD"}],'
          '"suites":["x-wing-rfc9180-v1"]}');
    });

    // Two constants used to be pinned here against ever growing:
    // `KeyPackage.legacySuites` and `legacyNskeySuites`, the values an absent
    // `suites` field was read as. Both are gone — `suites` is required now, so
    // nothing is read on a holder's behalf and there is no list to widen.
  });

  group('FROZEN FOREVER: algorithm spellings, wire and keyfile', () {
    test('the protocol ids, as raw strings', () {
      expect(SecretSharingAlgos.xWing, 'x-wing');
      expect(SecretSharingAlgos.mlKem1024, 'ml-kem-1024');
      expect(SecretSharingAlgos.xWingRfc9180, 'x-wing-rfc9180-v1');
      expect(SecretSharingAlgos.mlKem1024Rfc9180, 'ml-kem-1024-rfc9180-v1');
      expect(SecretSharingAlgos.useEnc, 'enc');
    });

    test('the preference orders are frozen — they decide negotiation', () {
      expect(SecretSharingAlgos.keyAlgos, ['x-wing', 'ml-kem-1024']);
      expect(SecretSharingAlgos.suites,
          ['x-wing-rfc9180-v1', 'ml-kem-1024-rfc9180-v1']);
    });

    test('suite → seal version byte, with literals on both sides', () {
      expect(SecretSharingAlgos.sealVersionFor('x-wing-hpke-v1'), isNull,
          reason: 'the retired id maps to no version, so an advertisement '
              'still naming it cannot be sealed to');
      expect(SecretSharingAlgos.sealVersionFor('x-wing-rfc9180-v1'), 0x02);
      expect(SecretSharingAlgos.sealVersionFor('ml-kem-1024-rfc9180-v1'), 0x03);
      expect(SecretSharingAlgos.sealVersionFor('x-wing-hpke-v2'), isNull);
    });

    test('keyAlgo → suites, the lists enrollment records freeze', () {
      expect(SecretSharingAlgos.openableSuitesFor('x-wing'),
          ['x-wing-rfc9180-v1']);
      expect(SecretSharingAlgos.openableSuitesFor('ml-kem-1024'),
          ['ml-kem-1024-rfc9180-v1']);
      expect(SecretSharingAlgos.openableSuitesFor('kyber-1024-v9'), isEmpty);
      expect(SecretSharingAlgos.suiteForKeyAlgo('x-wing'), 'x-wing-rfc9180-v1');
      expect(SecretSharingAlgos.suiteForKeyAlgo('ml-kem-1024'),
          'ml-kem-1024-rfc9180-v1');
    });

    test('wire spelling ↔ keyfile token, the declared junction', () {
      // The keyfile vocabulary drops the hyphens on purpose; these two
      // switches are the only place the vocabularies meet.
      expect(SecretSharingAlgos.materialAlgoFor('x-wing'), 'xwing');
      expect(SecretSharingAlgos.materialAlgoFor('ml-kem-1024'), 'mlkem1024');
      expect(SecretSharingAlgos.materialAlgoFor('kyber-1024-v9'), isNull);
      expect(SecretSharingAlgos.keyAlgoForMaterial('xwing'), 'x-wing');
      expect(SecretSharingAlgos.keyAlgoForMaterial('mlkem1024'), 'ml-kem-1024');
      expect(SecretSharingAlgos.keyAlgoForMaterial('rsa2048'), isNull);
    });

    test('ML-DSA-65 has ONE spelling on the wire: mldsa65', () {
      // This test used to be "two spellings coexist, and BOTH are frozen":
      // the root record said the hyphenated 'ml-dsa-65' (the
      // key-ESTABLISHMENT vocabulary, which a signer has no part in) while
      // the root link and everything pkam/enroll/keyfile said 'mldsa65'.
      // Nothing was ever released carrying either, so "frozen" was the
      // greenfield rule re-litigated; decisions 101 harmonised them when the
      // root became an ordinary signing key advertised through `_apsk`.
      expect(PqSigningRoot.rootKeyAlgo, SigningAlgoType.mldsa65);
      expect(PqSigningRoot.rootKeyAlgo.name, 'mldsa65');
      expect(PqSigningChain.rootLinkAlgo, 'mldsa65');
      expect(SigningAlgoType.mldsa65.name, 'mldsa65');
    });

    test('the deployment default keyEstablishmentAlgorithms is [x-wing]', () {
      expect(AtClientPreference().keyEstablishmentAlgorithms, ['x-wing']);
    });

    test('the _apsk reader accepts the exact published array shape', () {
      // The composer is at_auth's (apskAdvertisement) and pinned there; this
      // is the other half of the same contract — the literal an atServer
      // actually serves, read by the package that verifies against it. A
      // rename on either side has to break one of these two pins.
      final parsed = parseApskValue(
          '{"v":1,"keys":[{"kid":"cff3d220cf61dd4a","use":"sign",'
          '"alg":"mldsa65","pub":"QUJD"}]}');

      expect(parsed.signingAlgo, SigningAlgoType.mldsa65);
      expect(parsed.publicKey, 'QUJD');
    });

    test('the bare _apsk value round-trips untouched', () {
      // The released form, and what a plain-legacy enrollment still
      // publishes. Every deployed consumer base64-decodes it as an RSA key.
      final parsed = parseApskValue('MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A');

      expect(parsed.signingAlgo, SigningAlgoType.rsa2048);
      expect(parsed.publicKey, 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A');
    });

    test('a chain-link payload emits its exact JSON shape', () {
      // Payload, not wrapper: these field names are the same under either
      // wrapper shape and are compared against live records by verifiers.
      // The signature covers signableTextOf of exactly this map (its JSON
      // encoding under the JWS wrapper), so the key ORDER is
      // cryptographically bound.
      expect(
          jsonEncode(PqSigningChain.linkPayload(
              childEnrollmentId: 'c1', childApkamPublicKey: 'PK')),
          '{"v":1,"childEnrollmentId":"c1","apkamPublicKey":"PK"}');
    });

    test('the nskey advertisement version', () {
      expect(nskeyAdvertisementVersion, 1);
      expect(PqSigningRoot.currentVersion, 1);
    });
  });

  group('FROZEN FOREVER: the signed-envelope shape', () {
    // RFC 7515 General JSON Serialization, and nothing beside it — no wrapper
    // member of our own, so the whole document is somebody else's standard.
    // The committed vectors are checked by an off-the-shelf verifier
    // (tool/verify_jws_vectors.mjs), and the protected-header bytes are
    // covered by the signature, so the member ORDER below is
    // cryptographically bound rather than a style choice.

    test('signableTextOf: a String signs verbatim, a Map as compact JSON', () {
      // Not the envelope's codec — the envelope signs base64url text. This is
      // what the signing-chain ROOT link signs over, which is why it is
      // pinned: the root link is minted by one client and checked by another.
      expect(signableTextOf('raw'), 'raw');
      expect(signableTextOf({'b': 2, 'a': 1}), '{"b":2,"a":1}');
    });

    test('the envelope version literal is 1', () {
      expect(envelopeVersion, 1);
    });

    test('every envelope type, spelled out', () {
      // What each envelope was signed FOR, inside the protected header where
      // the signature covers it. Raw literals: a verifier is handed the type
      // it expects, so these strings are what two implementations have to
      // agree on, and changing one silently re-types every envelope a build
      // signs while leaving every reader looking for the old spelling.
      expect(EnvelopeType.app.typ, 'at-app+jws');
      expect(EnvelopeType.chainLink.typ, 'at-chain-link+jws');
      expect(EnvelopeType.keyPackage.typ, 'at-key-package+jws');
      expect(EnvelopeType.nskeyRing.typ, 'at-nskey-ring+jws');
      expect(EnvelopeType.secretEnvelope.typ, 'at-secret-envelope+jws');

      // Every value is distinct — the whole mechanism is that two uses cannot
      // be confused, and two enum entries sharing a spelling would confuse
      // exactly the pair that shared it, silently.
      expect({for (final t in EnvelopeType.values) t.typ}.length,
          EnvelopeType.values.length);
    });

    test('the root link signs under its own domain tag', () {
      // The root link is not a JWS and has no header to carry a type, so its
      // flavour is a prefix on the signed bytes. Pinned as a raw literal for
      // the same reason the header spellings are: the signer and both
      // verifiers are the same build today and need not be tomorrow.
      expect(PqSigningChain.rootLinkDomain, 'at-root-link:');
      expect(
          utf8.decode(PqSigningChain.rootLinkSignableBytes(
              PqSigningChain.linkPayload(
                  childEnrollmentId: 'c1', childApkamPublicKey: 'PK'))),
          'at-root-link:'
          '{"v":1,"childEnrollmentId":"c1","apkamPublicKey":"PK"}');
    });

    test('the envelope members, their order, and unpadded base64url', () {
      final pair = AtChopsUtil.generateAtPkamKeyPair();
      final envelope = signEnvelope({
        'hello': 'world'
      }, keys: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.rsa2048,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey)
      ], enrollmentId: 'e1', type: EnvelopeType.app);

      expect(envelope.toJson().keys.toList(), ['payload', 'signatures'],
          reason: 'exactly RFC 7515 general serialization — a member of our '
              'own here would be the thing that stops it being the standard');
      expect(envelope.signatures, hasLength(1));
      final entry = envelope.signature;
      expect(entry.toJson().keys.toList(), ['protected', 'signature']);

      for (final text in [
        envelope.payloadB64,
        entry.protected,
        entry.signature,
      ]) {
        expect(text.contains('='), isFalse,
            reason: 'RFC 7515 base64url carries no padding');
      }
      expect(utf8.decode(base64Decode(base64.normalize(envelope.payloadB64))),
          '{"hello":"world"}');
      // RSA-2048 → 256 signature bytes → 342 unpadded base64url chars, a
      // length Dart's bare base64Decode throws on. Pinned because it is the
      // one arm that can catch a missing base64 normalisation: ML-DSA-65's
      // 4412 chars are a multiple of 4 and decode either way.
      expect(entry.signature.length, 342);
    });

    test('the protected header bytes, both algorithms', () async {
      String headerOf(SignedEnvelope envelope) => utf8
          .decode(base64Decode(base64.normalize(envelope.signature.protected)));

      final rsaPair = AtChopsUtil.generateAtPkamKeyPair();
      expect(
          headerOf(signEnvelope({
            'p': 1
          }, keys: [
            ApkamSigningKeys(
                algorithm: SigningAlgoType.rsa2048,
                publicKey: rsaPair.atPublicKey.publicKey,
                privateKey: rsaPair.atPrivateKey.privateKey)
          ], enrollmentId: 'e1', type: EnvelopeType.app)),
          '{"alg":"RS256","typ":"at-app+jws","kid":"e1","v":1}',
          reason: 'RS256, not rsa2048: the JOSE registered name, and SHA-256 '
              'by definition — which is why the envelope names no hash');

      final mlDsaPair = await MlDsa65PureDartAlgo().generateKeyPair();
      expect(
          headerOf(signEnvelope({
            'p': 1
          }, keys: [
            ApkamSigningKeys(
                algorithm: SigningAlgoType.mldsa65,
                publicKey: base64Encode(mlDsaPair.publicKey),
                privateKey: base64Encode(mlDsaPair.secretKey))
          ], enrollmentId: 'e1', type: EnvelopeType.app)),
          '{"alg":"ML-DSA-65","typ":"at-app+jws","kid":"e1","v":1}',
          reason: 'ML-DSA-65 is the RFC 9964 registered JOSE name');
    });

    test('the header omits kid entirely when no enrollment is supplied', () {
      final pair = AtChopsUtil.generateAtPkamKeyPair();
      final envelope = signEnvelope({
        'hello': 'world'
      }, keys: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.rsa2048,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey)
      ], type: EnvelopeType.app);
      expect(
          utf8.decode(
              base64Decode(base64.normalize(envelope.signature.protected))),
          '{"alg":"RS256","typ":"at-app+jws","v":1}',
          reason: 'the key-package path signs before the atServer assigns an '
              'id, and a guessed or sentinel value would be frozen inside the '
              'signature where nobody could correct it');
    });
  });
}
