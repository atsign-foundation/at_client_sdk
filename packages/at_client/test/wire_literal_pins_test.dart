/// Exact-string pins over every wire literal the PQ refactor will relocate.
///
/// Almost every existing test asserts these values *through the constants that
/// define them* — `expect(x, SomeClass.someConst)` — which stays green when the
/// constant's VALUE changes. These pins assert the raw literals, so moving or
/// centralising a definition (the refactor's whole business) cannot silently
/// change what goes on the wire. On an intended wire change — there should be
/// none — the pin's edit is the review.
///
/// Two classes of pin, annotated per group:
///
/// - **FROZEN FOREVER** — wire contract: record names, provider ids,
///   payload field names, algorithm spellings, crypto bindings. Records
///   already written on live atServers carry these; several are immutable or
///   write-once. A red pin here means a wire break, full stop.
/// - **JWS-WILL-MOVE** — the *version-1* signed-envelope wrapper shape
///   (`v`:1, payload-as-Map, padded base64, `signableTextOf` bytes). The JWS
///   shape (version 2, `decisions.md` 60) is landed and readers accept both
///   wrappers; these pins stay binding because the producer still emits
///   version 1 by default. The 4.0 default flip retires them — not the
///   migration, which added the version-2 group beside them instead.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/crypto/nskey/nskey_mint_lock.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
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

    test('the mint lock is _nskeylock.<ns>@<owner>, immutable, 2-minute ttl',
        () {
      final key = NskeyMintLock(atClient).keyFor('@alice', 'app_1.my_apps');
      expect(key.toString(), '_nskeylock.app_1.my_apps@alice');
      // The atServer's second-immutable-create refusal IS the interlock, so
      // the metadata is contract, not tuning.
      expect(key.metadata.immutable, isTrue);
      expect(key.metadata.ttl, 120000);
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
      expect(PqSigningRoot(atClient).keyFor('@alice').toString(),
          'public:pq_signing_root@alice');
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
      expect(NskeyPrivateFiling.secretNamePrefix, '__nskey.');
    });

    test('_apsk appMetadata link field names', () {
      expect(PqSigningChain.linkField, 'apskChainLink');
      expect(PqSigningChain.rootLinkField, 'apskRootLink');
    });

    test('keyfile ids for nskey privates and the root (at rest, frozen)', () {
      // Keyfile-only, but existing keyfiles hold these ids and scans match on
      // them, so they freeze the same way wire names do.
      expect(NskeyPrivateFiling.keyIdFor('app_1.my_apps', 'abc123'),
          'nskey.app_1.my_apps.abc123');
      expect(PqSigningRoot.keyId, 'pq_signing_root');
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
    });

    test('an ML-KEM conveyance carries the SAME XWING-prefixed info',
        () async {
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

    test('the pairwise substrate binds info "at_client/secret_sharing/v1"',
        () {
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

      await provider.encrypt(
          CryptoContext(atClient: atClient), atKey, 'hello');

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
          '{"kid":"d9cae0dbdbf078b2","use":"enc","alg":"x-wing","pub":"QUJD"}');
    });

    test('computeKid hashes the base64 TEXT, not the decoded bytes', () {
      // Accident-shaped and frozen: the kpid is the first 16 hex chars of
      // SHA-256 over the UTF-8 of the base64 STRING. sha256('QUJD') — not
      // sha256(base64Decode('QUJD')), whose prefix would be 'b5d4045c3f466f'.
      expect(PackageKey.computeKid('QUJD'), 'd9cae0dbdbf078b2');
    });

    test('a key package payload emits its exact JSON shape', () {
      final payload = KeyPackage.payloadFor(
        createdAt: DateTime.utc(2026, 6, 11),
        keys: [PackageKey(use: 'enc', alg: 'x-wing', pub: 'QUJD')],
      );
      expect(
          jsonEncode(payload),
          '{"v":1,"createdAt":"2026-06-11T00:00:00.000Z",'
          '"keys":[{"kid":"d9cae0dbdbf078b2","use":"enc","alg":"x-wing",'
          '"pub":"QUJD"}],'
          '"suites":["x-wing-rfc9180-v1","x-wing-hpke-v1"]}');
    });

    test('the legacy-suites lists must never grow', () {
      // A widened list changes what absent-`suites` packages are claimed to
      // open, on behalf of holders that never said so.
      expect(KeyPackage.legacySuites, ['x-wing-hpke-v1']);
      expect(legacyNskeySuites, ['x-wing-hpke-v1']);
    });
  });

  group('FROZEN FOREVER: algorithm spellings, wire and keyfile', () {
    test('the protocol ids, as raw strings', () {
      expect(SecretSharingAlgos.xWing, 'x-wing');
      expect(SecretSharingAlgos.mlKem1024, 'ml-kem-1024');
      expect(SecretSharingAlgos.xWingHpke, 'x-wing-hpke-v1');
      expect(SecretSharingAlgos.xWingRfc9180, 'x-wing-rfc9180-v1');
      expect(SecretSharingAlgos.mlKem1024Rfc9180, 'ml-kem-1024-rfc9180-v1');
      expect(SecretSharingAlgos.useEnc, 'enc');
    });

    test('the preference orders are frozen — they decide negotiation', () {
      expect(SecretSharingAlgos.keyAlgos, ['x-wing', 'ml-kem-1024']);
      expect(SecretSharingAlgos.suites,
          ['x-wing-rfc9180-v1', 'ml-kem-1024-rfc9180-v1', 'x-wing-hpke-v1']);
    });

    test('suite → seal version byte, with literals on both sides', () {
      expect(SecretSharingAlgos.sealVersionFor('x-wing-hpke-v1'), 0x01);
      expect(SecretSharingAlgos.sealVersionFor('x-wing-rfc9180-v1'), 0x02);
      expect(SecretSharingAlgos.sealVersionFor('ml-kem-1024-rfc9180-v1'), 0x03);
      expect(SecretSharingAlgos.sealVersionFor('x-wing-hpke-v2'), isNull);
    });

    test('keyAlgo → suites, the lists enrollment records freeze', () {
      expect(SecretSharingAlgos.openableSuitesFor('x-wing'),
          ['x-wing-rfc9180-v1', 'x-wing-hpke-v1']);
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

    test('two spellings of ML-DSA-65 coexist, and BOTH are frozen', () {
      // The immutable root record says 'ml-dsa-65' (hyphenated, matching the
      // advertised-key vocabulary); the root link and everything
      // pkam/enroll/keyfile say 'mldsa65'. Records already published carry
      // both — a harmonising refactor would break verification of one side.
      expect(PqSigningRoot.rootKeyAlgo, 'ml-dsa-65');
      expect(PqSigningChain.rootLinkAlgo, 'mldsa65');
      expect(SigningAlgoType.mldsa65.name, 'mldsa65');
    });

    test('the deployment default keyEstablishmentAlgo is x-wing', () {
      expect(AtClientPreference().keyEstablishmentAlgo, 'x-wing');
    });

    test('the tagged _apsk value emits its exact JSON shape', () {
      // Nothing in 3.x publishes this, but parseApskValue shipped, so the
      // format is a cross-release contract — not part of the JWS wrapper.
      expect(
          encodeTaggedApsk(
              signingAlgo: SigningAlgoType.mldsa65, publicKey: 'QUJD'),
          '{"v":1,"signingAlgo":"mldsa65","publicKey":"QUJD"}');
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

  group('JWS-WILL-MOVE: the version-1 signed-envelope wrapper', () {
    // The version-2 (JWS) shape is landed and readers accept both wrappers,
    // but the producer DEFAULT is still version 1, so this group remains the
    // emitted shape until the 4.0 flag flip retires it. The version-2 wrapper
    // has its own FROZEN group below.

    test('signableTextOf: a String signs verbatim, a Map as compact JSON', () {
      // The String arm is the migration lever itself: a JWS signing input
      // passes through it unchanged.
      expect(signableTextOf('raw'), 'raw');
      expect(signableTextOf({'b': 2, 'a': 1}), '{"b":2,"a":1}');
    });

    test('the wrapper version literal is 1', () {
      expect(signedEnvelopeVersion, 1);
    });

    test('signEnvelope: key order, field values, padded base64', () {
      final pair = AtChopsUtil.generateAtPkamKeyPair();
      final envelope = signEnvelope(
        {'hello': 'world'},
        keys: ApkamSigningKeys(
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey),
        enrollmentId: 'enroll-1',
      );

      expect(envelope.keys.toList(),
          ['v', 'payload', 'signature', 'hashingAlgo', 'signingAlgo',
              'enrollmentId']);
      expect(envelope['v'], 1);
      expect(envelope['payload'], {'hello': 'world'},
          reason: 'payload embeds as a Map, not a string — JWS changes this');
      expect(envelope['hashingAlgo'], 'sha256');
      expect(envelope['signingAlgo'], 'rsa2048');
      expect(envelope['enrollmentId'], 'enroll-1');
      // Standard base64 WITH padding: RSA-2048 → 256 bytes → 344 chars,
      // '=='-terminated. JWS flips to base64url-unpadded (342 chars), and
      // Dart's base64Decode throws on that — the migration's measured trap.
      final signature = envelope['signature'] as String;
      expect(signature.length, 344);
      expect(signature, endsWith('=='));
    });

    test('signEnvelope omits enrollmentId only when none is supplied', () {
      final pair = AtChopsUtil.generateAtPkamKeyPair();
      final envelope = signEnvelope(
        {'hello': 'world'},
        keys: ApkamSigningKeys(
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey),
      );
      expect(envelope.containsKey('enrollmentId'), isFalse,
          reason: 'the key-package path signs before the atServer assigns an '
              'id; the mixin path never omits it (it stamps "primary")');
    });
  });

  group('FROZEN FOREVER: the version-2 (JWS) signed-envelope wrapper', () {
    // RFC 7515 Flattened JSON Serialization. Frozen from birth: the shape is
    // somebody else's standard, the committed vectors are checked by an
    // off-the-shelf verifier, and the protected-header bytes are covered by
    // the signature — so the member ORDER here is cryptographically bound,
    // not a style choice.
    test('the version-2 wrapper: field order, unpadded base64url', () {
      final pair = AtChopsUtil.generateAtPkamKeyPair();
      final envelope = signEnvelope(
        {'hello': 'world'},
        keys: ApkamSigningKeys(
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey),
        enrollmentId: 'e1',
        version: 2,
      );

      expect(envelope.keys.toList(),
          ['v', 'payload', 'protected', 'signature']);
      expect(envelope['v'], 2);
      for (final member in ['payload', 'protected', 'signature']) {
        expect((envelope[member] as String).contains('='), isFalse,
            reason: 'RFC 7515 base64url carries no padding');
      }
      expect(
          utf8.decode(
              base64Decode(base64.normalize(envelope['payload'] as String))),
          '{"hello":"world"}');
    });

    test('the protected header bytes, both algorithms', () async {
      String headerOf(Map<String, Object?> envelope) => utf8.decode(
          base64Decode(base64.normalize(envelope['protected'] as String)));

      final rsaPair = AtChopsUtil.generateAtPkamKeyPair();
      expect(
          headerOf(signEnvelope({'p': 1},
              keys: ApkamSigningKeys(
                  publicKey: rsaPair.atPublicKey.publicKey,
                  privateKey: rsaPair.atPrivateKey.privateKey),
              enrollmentId: 'e1',
              version: 2)),
          '{"alg":"RS256","kid":"e1","v":2}',
          reason: 'RS256, not rsa2048: the JOSE registered name, and SHA-256 '
              'by definition — hashingAlgo has no version-2 equivalent');

      final mlDsaPair = await MlDsa65PureDartAlgo().generateKeyPair();
      expect(
          headerOf(signEnvelope({'p': 1},
              keys: ApkamSigningKeys(
                  publicKey: base64Encode(mlDsaPair.publicKey),
                  privateKey: base64Encode(mlDsaPair.secretKey)),
              enrollmentId: 'e1',
              signingAlgo: SigningAlgoType.mldsa65,
              version: 2)),
          '{"alg":"ML-DSA-65","kid":"e1","v":2}',
          reason: 'ML-DSA-65 is the RFC 9964 registered JOSE name');
    });
  });
}
