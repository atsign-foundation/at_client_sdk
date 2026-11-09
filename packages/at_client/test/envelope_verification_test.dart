import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show sha256;
import 'package:crypton/crypton.dart' as crypton;

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, KeyEntryStatus, apskAdvertisement;
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, RsaKeyPair, SigningAlgoType, XWingPureDartAlgo;
import 'package:at_client/at_client.dart'
    show
        EnvelopeKeySelected,
        EnvelopeRefusal,
        EnvelopeRefused,
        EnvelopeVerified,
        PublishedApsk,
        SecretSharingAlgos,
        maxPublishedApskLength,
        selectEnvelopeKey,
        verifySignedEnvelope;
import 'package:at_client/at_client_mixins.dart'
    show
        AtClientEnvelopeSigner,
        KeyPackage,
        KeyPackageStatus,
        PackageKey,
        WithdrawnSigningKeyException,
        verifyAdvertisedKeyPackage;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException, EnrollmentConstants;
import 'package:test/test.dart';

import 'test_utils/envelope_signers.dart';
import 'test_utils/envelope_tamper.dart';

/// Catalogue: features/at_client/envelope_verification.feature
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const e = 'enroll-e';
  late RsaKeyPair rsaPair;
  late Map<String, String> remoteData;
  late SigningClient ofE;
  late AtClientEnvelopeSigner ofBob;
  late SignedEnvelope envelope;

  setUpAll(() => rsaPair = RsaKeyPair.generate());

  setUp(() async {
    remoteData = {};
    ofE = await signingClient(alice, e, remoteData);
    ofBob = readerOf(bob, 'enroll-b', remoteData);
    envelope = await ofE.signer.wrapAndSign({'result': 1});
  });

  /// A bare RSA-2048 `_apsk` value, as an enrollment holding one RSA key
  /// publishes it.
  String bare() => rsaPair.atPublicKey.publicKey;

  /// The value of E's `_apsk` cut to each shape a verifier must refuse.
  final unreadable = <String, String Function(String bare, String array)>{
    'a bare RSA-2048 key truncated by one character': (bare, _) =>
        bare.substring(0, bare.length - 1),
    'a bare value carrying a character outside base64': (bare, _) =>
        '${bare.substring(0, 10)}!${bare.substring(11)}',
    'an array truncated halfway': (_, array) =>
        array.substring(0, array.length ~/ 2),
    "an array whose one entry's pub is truncated": (_, array) =>
        array.replaceFirstMapped(RegExp(r'"pub":"([^"]+)"'),
            (m) => '"pub":"${m[1]!.substring(0, m[1]!.length - 1)}"'),
    'an array listing only an algorithm this build lacks': (_, array) =>
        array.replaceAll('"alg":"mldsa65"', '"alg":"ed25519"'),
    'the empty string': (_, __) => '',
  };

  test('verifyEnvelopeSignature refuses an _apsk that cannot be read',
      () async {
    remoteData[apskUri(alice, e)] = unreadable.values.first(bare(), ofE.apsk);

    await expectLater(
        ofBob.verifyEnvelopeSignature(envelope, signerAtSign: alice),
        throwsA(isA<AtSigningVerificationException>()
            .having((x) => x.message, 'message', contains('_apsk'))));
  });

  test("A key package whose enrollment's _apsk cannot be read is rejected",
      () async {
    final keyPackage = await ofE.signer.wrapAndSign(
        KeyPackage.payloadFor(createdAt: DateTime.utc(2026), keys: [
          PackageKey(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.xWing,
              pub: base64Encode(
                  (await XWingPureDartAlgo.instance.generateKeyPair())
                      .publicKey))
        ]),
        type: EnvelopeType.keyPackage);
    remoteData[apskUri(alice, e)] =
        unreadable.values.elementAt(1)(bare(), ofE.apsk);

    final (_, status) = await verifyAdvertisedKeyPackage(keyPackage.toJson(),
        signer: AtClientEnvelopeSigner(
            readerOf(alice, 'enroll-g', remoteData).atClient,
            publicKeyCacheSettings: null),
        signerAtSign: alice,
        enrollmentId: e);

    expect(status, KeyPackageStatus.rejected);
  });

  group(
      'Given an entry naming no algorithm and an _apsk listing an ed25519 key',
      () {
    test(
        'when verifyEnvelope reads them, then it throws '
        'AtSigningVerificationException', () async {
      final noAlg = resigned(envelope, [ofE.key], (h) => h..remove('alg'));
      final ed25519 = jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey(kid: 'k-ed', alg: SigningAlgoType.ed25519, pub: 'AAAA')
      ]));

      await expectLater(
          verifyEnvelope(noAlg,
              signerPublicKey: ed25519,
              signerAtSign: alice,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });

  group('Given an _apsk value that cannot be read', () {
    for (final MapEntry(key: shape, value: cut) in unreadable.entries) {
      test(
          'when verifyEnvelope reads $shape, then it throws '
          'AtSigningVerificationException', () async {
        await expectLater(
            verifyEnvelope(envelope,
                signerPublicKey: cut(bare(), ofE.apsk),
                signerAtSign: alice,
                expecting: EnvelopeType.app),
            throwsA(isA<AtSigningVerificationException>()));
      });
    }
  });

  group('the offline facade', () {
    late ({Uint8List publicKey, Uint8List secretKey}) k2Pair;
    late SigningClient ofG;
    late SigningClient ofF;

    setUpAll(
        () async => k2Pair = await MlDsa65PureDartAlgo().generateKeyPair());

    setUp(() async {
      ofG = await signingClient(alice, 'enroll-g', remoteData);
      ofF = await signingClient(bob, 'enroll-f', remoteData);
    });

    // NOTE: recomputed from first principles rather than by the helper
    // production uses, so a kid in a result is checked against its key.
    String kidOf(String pub) =>
        sha256.convert(base64Decode(pub)).toString().substring(0, 16);
    String kidK() => kidOf(ofE.key.publicKey);
    String kidK2() => kidOf(base64Encode(k2Pair.publicKey));
    String kidR() => kidOf(rsaPair.atPublicKey.publicKey);

    ApkamSigningKeys keyR() => ApkamSigningKeys(
        algorithm: SigningAlgoType.rsa2048,
        publicKey: rsaPair.atPublicKey.publicKey,
        privateKey: rsaPair.atPrivateKey.privateKey);

    ApskSigningKey listedK([KeyEntryStatus status = KeyEntryStatus.active]) =>
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.mldsa65,
            pub: ofE.key.publicKey,
            status: status);
    ApskSigningKey listedK2() => ApskSigningKey.forPublicKey(
        alg: SigningAlgoType.mldsa65, pub: base64Encode(k2Pair.publicKey));
    ApskSigningKey listedR() => ApskSigningKey.forPublicKey(
        alg: SigningAlgoType.rsa2048, pub: rsaPair.atPublicKey.publicKey);

    PublishedApsk apskOfE([List<ApskSigningKey>? listed]) => PublishedApsk(
        atSign: alice,
        enrollmentId: e,
        value: listed == null
            ? ofE.apsk
            : jsonEncode(apskAdvertisement(keys: listed)));

    SignedEnvelope signedByE(List<ApkamSigningKeys> keys,
            {EnvelopeType type = EnvelopeType.app, String? enid = e}) =>
        signEnvelope({'result': 1},
            keys: keys, type: type, atSign: alice, enrollmentId: enid);

    test('A valid envelope verifies against its signer\'s published _apsk',
        () async {
      final result = await verifySignedEnvelope(envelope,
          signer: PublishedApsk(
              atSign: alice,
              enrollmentId: e,
              value: remoteData[apskUri(alice, e)]!));

      expect(
          result,
          isA<EnvelopeVerified>()
              .having((r) => r.signer.atSign, 'atSign', alice)
              .having((r) => r.signer.enrollmentId, 'enrollmentId', e)
              .having((r) => r.kid, 'kid', kidK())
              .having((r) => r.algorithm, 'algorithm', SigningAlgoType.mldsa65)
              .having((r) => r.keyStatus, 'keyStatus', KeyEntryStatus.active)
              .having((r) => r.issuerConfirmed, 'issuerConfirmed', isTrue));
    });

    test(
        'fetchPublishedApsk returns the _apsk an enrollment published, with '
        'whose it is', () async {
      final fetched = await ofBob.fetchPublishedApsk(alice, e);

      expect(fetched.atSign, alice);
      expect(fetched.enrollmentId, e);
      expect(fetched.value, remoteData[apskUri(alice, e)]);
    });

    test('fetchPublishedApsk refuses an enrollment the atServer has revoked',
        () async {
      final cachingByDefault = AtClientEnvelopeSigner(ofBob.atClient);
      await cachingByDefault.fetchPublishedApsk(alice, e);
      remoteData['public:_apsk.$e.${EnrollmentConstants.perEnrollmentRevoked}'
          '$alice'] = remoteData.remove(apskUri(alice, e))!;

      await expectLater(
          cachingByDefault.fetchPublishedApsk(alice, e),
          throwsA(isA<WithdrawnSigningKeyException>()
              .having((x) => x.location, 'location', 'r.__e')),
          reason: 'with the default cache, a fetch a moment ago does not '
              'answer for one now');
      expect(
          (await cachingByDefault.fetchPublishedApsk(alice, e, cached: true))
              .value,
          ofE.apsk,
          reason: 'the control: a cached read returns what was fetched before');
    });

    test('A payload changed by one byte does not verify', () async {
      final changed = envelope.withPayloadJson({'result': 2});

      final result = await verifySignedEnvelope(changed, signer: apskOfE());

      expect(result, refusedAs(EnvelopeRefusal.badSignature, kid: kidK()));
    });

    test(
        'An envelope is refused against the _apsk of an Atsign it does not '
        'name', () async {
      final result = await verifySignedEnvelope(envelope,
          signer: PublishedApsk(
              atSign: bob, enrollmentId: 'enroll-f', value: ofF.apsk));

      expect(
          result,
          refusedAs(EnvelopeRefusal.wrongAtSign,
              kid: kidK(), naming: ['"@alice"', '"@bob"']));
    });

    group(
        "Given @bob's _apsk under the envelope's own enrollment id, listing "
        'the key that signed it', () {
      test('when verified, then it is refused with wrongAtSign', () async {
        final sameKeyAsBob =
            PublishedApsk(atSign: bob, enrollmentId: e, value: ofE.apsk);

        expect(
            await verifySignedEnvelope(envelope, signer: sameKeyAsBob),
            refusedAs(EnvelopeRefusal.wrongAtSign,
                kid: kidK(), naming: ['"@alice"', '"@bob"']));
        expect(await verifySignedEnvelope(envelope, signer: apskOfE()),
            isA<EnvelopeVerified>(),
            reason: 'the control: the same enrollment id and value as '
                "@alice's verifies, so the Atsign is all that differs");
      });
    });

    test(
        'An envelope that names no Atsign verifies, and says the signature '
        'does not confirm the Atsign', () async {
      final unnamed = claimless(envelope, [ofE.key]);

      final result = await verifySignedEnvelope(unnamed, signer: apskOfE());

      expect(
          result,
          isA<EnvelopeVerified>()
              .having((r) => r.kid, 'kid', kidK())
              .having((r) => r.issuerConfirmed, 'issuerConfirmed', isFalse));
    });

    test(
        'An envelope is refused against the _apsk of an enrollment it does '
        'not name', () async {
      final result = await verifySignedEnvelope(envelope,
          signer: PublishedApsk(
              atSign: alice, enrollmentId: 'enroll-g', value: ofG.apsk));

      expect(
          result,
          refusedAs(EnvelopeRefusal.wrongEnrollment,
              kid: kidK(), naming: ['"enroll-e"', '"enroll-g"']));
    });

    test('An envelope that names no enrollment is refused', () async {
      final result = await verifySignedEnvelope(
          signedByE([ofE.key], enid: null),
          signer: apskOfE());

      expect(
          result,
          refusedAs(EnvelopeRefusal.wrongEnrollment,
              kid: kidK(), naming: ['names no enrollment']));
    });

    test('An envelope signed for another purpose is refused', () async {
      final result = await verifySignedEnvelope(
          signedByE([ofE.key], type: EnvelopeType.keyPackage),
          signer: apskOfE());

      expect(
          result,
          refusedAs(EnvelopeRefusal.wrongType,
              kid: kidK(), naming: ['"at-key-package+jws"', '"at-app+jws"']));
    });

    for (final (shape, fault) in [
      ('a bare RSA-2048 key truncated by one character', 'not base64'),
      ('a bare value carrying a character outside base64', 'not base64'),
      ('an array truncated halfway', 'not valid JSON'),
      ("an array whose one entry's pub is truncated", 'not base64'),
      (
        'an array listing only an algorithm this build lacks',
        'no key this build can verify with'
      ),
      ('the empty string', 'is empty'),
    ]) {
      test('A malformed or truncated _apsk is refused with a reason: $shape',
          () async {
        final result = await verifySignedEnvelope(envelope,
            signer: apskOfE()._withValue(unreadable[shape]!(bare(), ofE.apsk)));

        expect(
            result,
            refusedAs(EnvelopeRefusal.malformedKeySet,
                kid: kidK(), naming: [fault]));
      });
    }

    test('A key the owner retired still verifies, and says so', () async {
      final result = await verifySignedEnvelope(envelope,
          signer: apskOfE([listedK(KeyEntryStatus.retired), listedK2()]));

      expect(
          result,
          isA<EnvelopeVerified>()
              .having((r) => r.kid, 'kid', kidK())
              .having((r) => r.keyStatus, 'keyStatus', KeyEntryStatus.retired));
    });

    test('A key the _apsk does not list is refused', () async {
      final result =
          await verifySignedEnvelope(envelope, signer: apskOfE([listedK2()]));

      expect(
          result,
          refusedAs(EnvelopeRefusal.keyNotInKeySet,
              kid: kidK(), naming: ['"${kidK()}"', '"${kidK2()}"']));
    });

    test(
        'A key the _apsk lists under a status this build does not know is '
        'refused', () async {
      final result = await verifySignedEnvelope(envelope,
          signer: apskOfE(
              [listedK(const KeyEntryStatus.of('suspended')), listedK2()]));

      expect(
          result,
          refusedAs(EnvelopeRefusal.keyNotVouchedFor,
              kid: kidK(), naming: ['"suspended"']));
    });

    group(
        "Given an _apsk whose only entry lists the envelope's key under a "
        'status this build does not know', () {
      test('when verified, then it is refused with keyNotVouchedFor', () async {
        expect(
            await verifySignedEnvelope(envelope,
                signer:
                    apskOfE([listedK(const KeyEntryStatus.of('suspended'))])),
            refusedAs(EnvelopeRefusal.keyNotVouchedFor,
                kid: kidK(), naming: ['"suspended"']));
      });
    });

    test(
        'An envelope verifies against an _apsk read before its enrollment '
        'was revoked', () async {
      final readAtT0 = await ofBob.fetchPublishedApsk(alice, e);
      remoteData['public:_apsk.$e.${EnrollmentConstants.perEnrollmentRevoked}'
          '$alice'] = remoteData.remove(apskUri(alice, e))!;

      final result = await verifySignedEnvelope(envelope, signer: readAtT0);

      expect(
          result, isA<EnvelopeVerified>().having((r) => r.kid, 'kid', kidK()));
      await expectLater(ofBob.fetchPublishedApsk(alice, e),
          throwsA(isA<WithdrawnSigningKeyException>()),
          reason: 'the control: the atServer did move it');
    });

    test(
        'An envelope verifies under the strongest algorithm it shares with '
        'the _apsk, and names it', () async {
      final result = await verifySignedEnvelope(signedByE([keyR()]),
          signer: apskOfE([listedK(), listedR()]));

      expect(
          result,
          isA<EnvelopeVerified>().having((r) => r.kid, 'kid', kidR()).having(
              (r) => r.algorithm, 'algorithm', SigningAlgoType.rsa2048));
    });

    test(
        "A caller's minimum algorithm refuses an envelope that verifies only "
        'under a weaker one', () async {
      final result = await verifySignedEnvelope(signedByE([keyR()]),
          signer: apskOfE([listedK(), listedR()]),
          minimumAlgorithm: SigningAlgoType.mldsa65);

      expect(
          result,
          refusedAs(EnvelopeRefusal.algorithmTooWeak,
              kid: kidR(), naming: ['rsa2048', 'mldsa65']));
    });

    test(
        'selectEnvelopeKey names the key and status verification would use, '
        'without the payload', () {
      final entriesOnly = SignedEnvelope.fromJson(
          {'payload': '', 'signatures': envelope.toJson()['signatures']});

      final selection = selectEnvelopeKey(entriesOnly, signer: apskOfE());

      expect(
          selection,
          isA<EnvelopeKeySelected>()
              .having((r) => r.kid, 'kid', kidK())
              .having((r) => r.algorithm, 'algorithm', SigningAlgoType.mldsa65)
              .having((r) => r.keyStatus, 'keyStatus', KeyEntryStatus.active)
              .having((r) => r.issuerConfirmed, 'issuerConfirmed', isTrue));
    });

    test(
        'selectEnvelopeKey reports a retired key, so a caller can refuse it '
        'at receipt', () {
      final selection = selectEnvelopeKey(envelope,
          signer: apskOfE([listedK(KeyEntryStatus.retired), listedK2()]));

      expect(
          selection,
          isA<EnvelopeKeySelected>()
              .having((r) => r.kid, 'kid', kidK())
              .having((r) => r.keyStatus, 'keyStatus', KeyEntryStatus.retired)
              .having((r) => r.key.offeredForNewOperations,
                  'offeredForNewOperations', isFalse));
    });

    test(
        'selectEnvelopeKey refuses an _apsk that cannot be read, without '
        'throwing', () {
      final selection = selectEnvelopeKey(envelope,
          signer: apskOfE()._withValue(
              unreadable['an array truncated halfway']!(bare(), ofE.apsk)));

      expect(
          selection, refusedAs(EnvelopeRefusal.malformedKeySet, kid: kidK()));
    });

    for (final (listed, carried, outcome) in [
      (
        'K and an RSA-2048 key R',
        'an ML-DSA-65 signature by K and an RS256 signature by R',
        'kid K'
      ),
      (
        'R only',
        'an ML-DSA-65 signature by K and an RS256 signature by R',
        'kid R'
      ),
      (
        'K only',
        'an RS256 signature by R only',
        'EnvelopeRefused with keyNotInKeySet'
      ),
    ]) {
      test(
          'selectEnvelopeKey and verifySignedEnvelope choose the same key: '
          '$listed, $carried', () async {
        final signer = apskOfE(switch (listed) {
          'R only' => [listedR()],
          'K only' => [listedK()],
          _ => [listedK(), listedR()],
        });
        final signed =
            signedByE(carried.contains('only') ? [keyR()] : [ofE.key, keyR()]);

        final selection = selectEnvelopeKey(signed, signer: signer);
        final verification = await verifySignedEnvelope(signed, signer: signer);

        switch (outcome) {
          case 'kid K' || 'kid R':
            final kid = outcome == 'kid K' ? kidK() : kidR();
            expect(selection,
                isA<EnvelopeKeySelected>().having((r) => r.kid, 'kid', kid));
            expect(verification,
                isA<EnvelopeVerified>().having((r) => r.kid, 'kid', kid));
          default:
            expect(selection, refusedAs(EnvelopeRefusal.keyNotInKeySet));
            expect(verification, refusedAs(EnvelopeRefusal.keyNotInKeySet));
        }
      });
    }

    test('The same envelope presented twice verifies twice', () async {
      final first = await verifySignedEnvelope(
          SignedEnvelope.parse(jsonEncode(envelope.toJson()), maxLength: 65536),
          signer: apskOfE()) as EnvelopeVerified;
      final second = await verifySignedEnvelope(
          SignedEnvelope.parse(jsonEncode(envelope.toJson()), maxLength: 65536),
          signer: apskOfE()) as EnvelopeVerified;

      expect([second.signer.atSign, second.signer.enrollmentId, second.kid],
          [first.signer.atSign, first.signer.enrollmentId, first.kid]);
      expect([second.algorithm, second.keyStatus],
          [first.algorithm, first.keyStatus]);
    });

    test(
        "Envelope text over the caller's bound in UTF-8 bytes is refused "
        'before it is decoded', () {
      final text = '${'é' * 30000}${'a' * 10000}';
      expect([text.length, utf8.encode(text).length], [40000, 70000],
          reason: 'the premise');

      expect(
          () => SignedEnvelope.parse(text, maxLength: 65536),
          throwsA(isA<AtSigningVerificationException>()
              .having((x) => x.message, 'message', contains('65536 bytes'))));
      expect(
          () => SignedEnvelope.parse(text, maxLength: 70000),
          throwsA(isA<AtSigningVerificationException>()
              .having((x) => x.message, 'message', contains('not JSON'))),
          reason: 'the control: at its exact length the same text is decoded, '
              'and refused as what it is');
    });

    test('An _apsk value over the cap is refused before it is read', () async {
      final result = await verifySignedEnvelope(envelope,
          signer: apskOfE()._withValue('x' * (maxPublishedApskLength + 1)));

      expect(
          result,
          refusedAs(EnvelopeRefusal.oversize,
              naming: ['$maxPublishedApskLength bytes']));
      expect(
          await verifySignedEnvelope(envelope,
              signer: apskOfE()._withValue('x' * maxPublishedApskLength)),
          isA<EnvelopeRefused>().having(
              (r) => r.refusal, 'refusal', isNot(EnvelopeRefusal.oversize)),
          reason: 'the control: at the cap the value is read');
    });

    group('Given a PublishedApsk whose value is over maxPublishedApskLength',
        () {
      test('when its keys are read, then it throws naming the cap', () {
        expect(
            () => apskOfE()._withValue('x' * (maxPublishedApskLength + 1)).keys,
            throwsA(isA<AtSigningVerificationException>().having(
                (x) => x.message,
                'message',
                contains('$maxPublishedApskLength bytes'))));
        expect(apskOfE()._withValue('x' * maxPublishedApskLength).keys,
            hasLength(1),
            reason: 'the control: at the cap the value is read, as one bare '
                'key');
      });
    });

    group('Given an envelope whose selected entry names no key', () {
      test(
          'when verified or selected, then it is refused as malformedEnvelope '
          'naming no kid', () async {
        final noKid = resigned(envelope, [ofE.key], (h) => h..remove('kid'));

        expect(selectEnvelopeKey(noKid, signer: apskOfE()), noKidRefusal);
        expect(
            await verifySignedEnvelope(noKid, signer: apskOfE()), noKidRefusal);
      });
    });

    group("Given an _apsk listing the envelope's kid under another algorithm",
        () {
      test('when verified, then it is refused with keyNotInKeySet', () async {
        final underRsa = ApskSigningKey(
            kid: kidK(),
            alg: SigningAlgoType.rsa2048,
            pub: rsaPair.atPublicKey.publicKey);

        expect(
            await verifySignedEnvelope(envelope,
                signer: apskOfE()._withValue(jsonEncode(
                    apskAdvertisement(keys: [underRsa, listedK2()])))),
            refusedAs(EnvelopeRefusal.keyNotInKeySet, kid: kidK()));
      });
    });

    group('Given a PublishedApsk built from "@Alice", "alice" or "@alice"', () {
      test('when it is read, then its atSign is "@alice"', () {
        for (final spelt in ['@Alice', 'alice', '@alice']) {
          expect(
              PublishedApsk(atSign: spelt, enrollmentId: e, value: '').atSign,
              alice);
        }
      });
    });

    group('Given an envelope whose iss is "@Alice"', () {
      test(
          'when verified against PublishedApsk(atSign: "alice"), then it '
          'verifies with issuerConfirmed true', () async {
        final spelt =
            resigned(envelope, [ofE.key], (h) => h..['iss'] = '@Alice');

        final result = await verifySignedEnvelope(spelt,
            signer: PublishedApsk(
                atSign: 'alice', enrollmentId: e, value: ofE.apsk));

        expect(
            result,
            isA<EnvelopeVerified>()
                .having((r) => r.issuerConfirmed, 'c', true));
      });
    });

    group('Given an envelope whose iss is not an Atsign', () {
      test(
          'when verified, then it is refused with wrongAtSign and nothing is '
          'thrown', () async {
        final notAnAtsign =
            resigned(envelope, [ofE.key], (h) => h..['iss'] = '@al ice');

        expect(await verifySignedEnvelope(notAnAtsign, signer: apskOfE()),
            refusedAs(EnvelopeRefusal.wrongAtSign, naming: ['"@al ice"']));
      });
    });

    group(
        'Given an envelope whose enid differs from the supplied enrollment id '
        'only in case', () {
      test('when verified, then it is not refused with wrongEnrollment',
          () async {
        final spelt =
            resigned(envelope, [ofE.key], (h) => h..['enid'] = 'ENROLL-E');

        expect(await verifySignedEnvelope(spelt, signer: apskOfE()),
            isA<EnvelopeVerified>());
      });
    });

    group('Given fetchPublishedApsk called with "@ALICE"', () {
      test('when it returns, then its atSign is "@alice"', () async {
        expect((await ofBob.fetchPublishedApsk('@ALICE', e)).atSign, alice);
      });
    });

    group('Given a protected header whose v nests 200,000 arrays', () {
      test(
          'when it is read, then it is refused naming its kind, and nothing '
          'else is thrown', () async {
        final header = '{"alg":"ML-DSA-65","typ":"at-app+jws","kid":"k",'
            '"v":${'[' * 200000}${']' * 200000}}';

        Object? outcome;
        try {
          final nested = SignedEnvelope.fromJson({
            'payload': 'e30',
            'signatures': [
              {'protected': b64u(header), 'signature': 'AA'}
            ],
          });
          outcome = await verifySignedEnvelope(nested,
              signer:
                  PublishedApsk(atSign: alice, enrollmentId: e, value: 'x'));
        } on AtSigningVerificationException catch (refusal) {
          outcome = refusal;
        }

        expect(
            outcome,
            isA<AtSigningVerificationException>()
                .having((x) => x.message, 'message', contains('JSON array')));
      });
    });

    group("Given an _apsk entry whose status nests 250,000 arrays", () {
      test(
          'when an envelope is verified against it, then it is refused as '
          'malformedKeySet', () async {
        final value = '{"v":1,"keys":[{"kid":"${kidK()}","use":"sign",'
            '"alg":"mldsa65","pub":"${ofE.key.publicKey}","status":'
            '${'[' * 250000}${']' * 250000}}]}';
        expect(utf8.encode(value).length, lessThan(maxPublishedApskLength),
            reason: 'the premise: under the cap, so it is read');

        expect(
            await verifySignedEnvelope(envelope,
                signer: apskOfE()._withValue(value)),
            refusedAs(EnvelopeRefusal.malformedKeySet,
                kid: kidK(), naming: ['JSON array']));
        expect(selectEnvelopeKey(envelope, signer: apskOfE()._withValue(value)),
            refusedAs(EnvelopeRefusal.malformedKeySet));
      });
    });

    group('Given a protected header member of the wrong JSON kind', () {
      test('when it is read, then it is refused naming the kind', () {
        for (final (member, value, kind) in [
          ('alg', 7, 'number'),
          ('typ', null, 'null'),
          ('kid', <Object?>[], 'array'),
          ('enid', 7, 'number'),
          ('v', '1', 'string'),
          ('v', <String, Object?>{}, 'object'),
        ]) {
          expect(
              () => resigned(envelope, [ofE.key], (h) => h..[member] = value),
              throwsA(isA<AtSigningVerificationException>()
                  .having((x) => x.message, 'message', contains('JSON $kind'))),
              reason: '$member as a JSON $kind');
        }
        expect(
            resigned(envelope, [ofE.key], (h) => h..['v'] = 2)
                .signature
                .version,
            2,
            reason: 'the control: an integer v of another value is read, and '
                'refused when verified');
      });
    });

    group('Given an _apsk RSA key whose public exponent has 3,000,001 bits',
        () {
      /// A bare `_apsk` value: [rsaPair]'s modulus with [exponent], as an
      /// X.509 SubjectPublicKeyInfo.
      String bareWithExponent(Uint8List exponent) {
        final modulus = _magnitude(
            crypton.RSAPublicKey.fromString(rsaPair.atPublicKey.publicKey)
                .asPointyCastle
                .modulus!);
        return base64Encode(_der(0x30, [
          ..._der(0x30, [
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, //
            0x05, 0x00,
          ]),
          ..._der(0x03, [
            0x00,
            ..._der(0x30, [..._derInteger(modulus), ..._derInteger(exponent)]),
          ]),
        ]));
      }

      SignedEnvelope signedBy(String bare) => SignedEnvelope.fromJson({
            'payload': b64u('{"result":1}'),
            'signatures': [
              {
                'protected': b64u(jsonEncode({
                  'alg': 'RS256',
                  'typ': 'at-app+jws',
                  'kid': kidOf(bare),
                  'iss': alice,
                  'enid': e,
                  'v': 1,
                })),
                'signature': b64u(String.fromCharCodes(List.filled(256, 1))),
              }
            ],
          });

      test(
          'when an envelope is verified against it, then it is refused before '
          'any signature is checked', () async {
        final huge = Uint8List(375001)
          ..[0] = 1
          ..[375000] = 1;
        final bare = bareWithExponent(huge);
        expect(bare.length, lessThan(maxPublishedApskLength),
            reason: 'the premise: under the cap, so it is read');
        final before = envelopeSignatureChecks;
        final clock = Stopwatch()..start();

        final result = await verifySignedEnvelope(signedBy(bare),
            signer: apskOfE()._withValue(bare));

        clock.stop();
        expect(result,
            refusedAs(EnvelopeRefusal.malformedKeySet, naming: ['exponent']));
        expect(envelopeSignatureChecks - before, 0);
        await expectLater(
            verifyEnvelope(signedBy(bare),
                signerPublicKey: bare,
                signerAtSign: alice,
                expecting: EnvelopeType.app),
            throwsA(isA<AtSigningVerificationException>()
                .having((x) => x.message, 'message', contains('exponent'))));
        printOnFailure('refused in ${clock.elapsedMilliseconds} ms');

        final f4 = bareWithExponent(Uint8List.fromList([0x01, 0x00, 0x01]));
        expect(
            await verifySignedEnvelope(signedBy(f4),
                signer: apskOfE()._withValue(f4)),
            refusedAs(EnvelopeRefusal.badSignature),
            reason: 'the control: the same key with exponent 65537 reaches the '
                'signature check');
      }, timeout: const Timeout(Duration(seconds: 60)));
    });

    group('Given a typ, enid or kid carrying a newline or a control character',
        () {
      SignedEnvelope unsigned(Map<String, Object?> header) =>
          SignedEnvelope.fromJson({
            'payload': 'e30',
            'signatures': [
              {'protected': b64u(jsonEncode(header)), 'signature': 'AA'}
            ],
          });
      final base = {
        'alg': 'ML-DSA-65',
        'typ': 'at-app+jws',
        'kid': 'k',
        'iss': alice,
        'enid': e,
        'v': 1,
      };

      test('when refused, then the reason is one line, escaped and bounded',
          () async {
        for (final (member, value, refusal) in [
          ('typ', 'x\nsecond line', EnvelopeRefusal.wrongType),
          ('typ', 'x\u2028y\u202ez', EnvelopeRefusal.wrongType),
          ('enid', 'enroll-e\r\nsecond line', EnvelopeRefusal.wrongEnrollment),
          ('kid', 'k\nsecond line', EnvelopeRefusal.keyNotInKeySet),
          ('typ', 'x' * 10000, EnvelopeRefusal.wrongType),
        ]) {
          final result = await verifySignedEnvelope(
              unsigned({...base, member: value}),
              signer: apskOfE());

          expect(result, refusedAs(refusal), reason: member);
          final reason = (result as EnvelopeRefused).reason;
          expect(
              reason.runes.where((r) => r < 0x20 || r == 0x2028 || r == 0x202e),
              isEmpty,
              reason: '$member: $reason');
          expect(reason.length, lessThan(400), reason: member);
        }
        final escaped = await verifySignedEnvelope(
            unsigned({...base, 'typ': 'x\nsecond line'}),
            signer: apskOfE()) as EnvelopeRefused;
        expect(escaped.reason, contains(r'"x\u000asecond line"'),
            reason: 'the newline is shown, escaped');
      });
    });

    group('Given any malformed envelope or _apsk value', () {
      test(
          'when selected and verified, then both refuse it the same way and '
          'nothing is thrown', () async {
        // NOTE: null where selection finds the key and only the signature is
        // refused.
        final envelopes = <(SignedEnvelope, EnvelopeRefusal?)>[
          (envelope.withEntryMember('signature', '!!not base64url!!'), null),
          (
            resigned(envelope, [ofE.key], (h) => h..remove('kid')),
            EnvelopeRefusal.malformedEnvelope
          ),
          (
            resigned(envelope, [ofE.key], (h) => h..['v'] = 2),
            EnvelopeRefusal.unsupportedVersion
          ),
          (
            resigned(envelope, [ofE.key], (h) => h..remove('typ')),
            EnvelopeRefusal.wrongType
          ),
          (
            resigned(envelope, [ofE.key], (h) => h..remove('enid')),
            EnvelopeRefusal.wrongEnrollment
          ),
          (
            resigned(envelope, [ofE.key], (h) => h..remove('alg')),
            EnvelopeRefusal.keyNotInKeySet
          ),
          (envelope.withEntryMember('signature', ''), null),
        ];
        final values = [
          for (final cut in unreadable.values) cut(bare(), ofE.apsk),
          'x' * (maxPublishedApskLength + 1),
          jsonEncode({'v': 1, 'keys': 'none'}),
          '[1, 2]',
          '{"v": 1, "keys": [{"kid": "k", "use": "sign", "alg": "mldsa65", '
              '"pub": "AAAA"}]}',
        ];
        var checked = 0;
        for (final (candidate, selectedAs) in envelopes) {
          final selection = selectEnvelopeKey(candidate, signer: apskOfE());
          final verification =
              await verifySignedEnvelope(candidate, signer: apskOfE());
          if (selectedAs == null) {
            expect(selection, isA<EnvelopeKeySelected>(), reason: '$candidate');
            expect(verification, isA<EnvelopeRefused>(), reason: '$candidate');
          } else {
            expect(selection, refusedAs(selectedAs), reason: '$candidate');
            expect(verification, refusedAs(selectedAs), reason: '$candidate');
          }
          checked++;
          for (final value in values) {
            final signer = apskOfE()._withValue(value);
            final selected = selectEnvelopeKey(candidate, signer: signer);
            expect(
                await verifySignedEnvelope(candidate, signer: signer),
                selected is EnvelopeRefused
                    ? refusedAs(selected.refusal)
                    : isA<EnvelopeRefused>(),
                reason: '$candidate against ${value.length} chars');
            checked++;
          }
        }
        for (final value in values) {
          expect(
              await verifySignedEnvelope(envelope,
                  signer: apskOfE()._withValue(value)),
              isA<EnvelopeRefused>());
          checked++;
        }
        expect(checked, envelopes.length * (values.length + 1) + values.length);
      });
    });

    group(
        'Given an envelope refused for its type, Atsign, enrollment or '
        'algorithm whose signature is also corrupted', () {
      test('when verified, then the refusal is that one and not badSignature',
          () async {
        SignedEnvelope corrupted(SignedEnvelope e) =>
            e.withEntryMember('signature', 'AAAA');
        final cases = [
          (
            corrupted(signedByE([ofE.key], type: EnvelopeType.keyPackage)),
            apskOfE(),
            null,
            EnvelopeRefusal.wrongType
          ),
          (
            corrupted(envelope),
            PublishedApsk(
                atSign: bob, enrollmentId: 'enroll-f', value: ofF.apsk),
            null,
            EnvelopeRefusal.wrongAtSign
          ),
          (
            corrupted(envelope),
            PublishedApsk(
                atSign: alice, enrollmentId: 'enroll-g', value: ofG.apsk),
            null,
            EnvelopeRefusal.wrongEnrollment
          ),
          (
            corrupted(signedByE([keyR()])),
            apskOfE([listedK(), listedR()]),
            SigningAlgoType.mldsa65,
            EnvelopeRefusal.algorithmTooWeak
          ),
        ];
        for (final (candidate, signer, minimum, refusal) in cases) {
          expect(
              await verifySignedEnvelope(candidate,
                  signer: signer, minimumAlgorithm: minimum),
              refusedAs(refusal));
        }
        expect(
            await verifySignedEnvelope(corrupted(envelope), signer: apskOfE()),
            refusedAs(EnvelopeRefusal.badSignature),
            reason: 'the control: with nothing else wrong, the corruption is '
                'what is refused');
      });
    });

    group('Given an _apsk that also lists an entry whose key is not base64',
        () {
      test(
          'when an envelope signed by its active key is verified, then it '
          'verifies', () async {
        final value = jsonEncode({
          ...apskAdvertisement(keys: [listedK()]),
          'keys': [
            ...apskAdvertisement(keys: [listedK()])['keys'] as List,
            {'kid': 'k-ed', 'use': 'sign', 'alg': 'ed25519', 'pub': 'not!b64'},
          ],
        });

        expect(
            await verifySignedEnvelope(envelope,
                signer: apskOfE()._withValue(value)),
            isA<EnvelopeVerified>().having((r) => r.kid, 'kid', kidK()));
        await verifyEnvelope(envelope,
            signerPublicKey: value,
            signerAtSign: alice,
            expecting: EnvelopeType.app);
      });
    });

    group(
        'Given an envelope whose signature is spelt padded or in the '
        'standard base64 alphabet', () {
      test('when verified, then it is refused as malformedEnvelope', () async {
        final unpadded = envelope.signature.signature;
        final standard =
            base64Encode(base64Url.decode(base64Url.normalize(unpadded)));
        expect(standard, isNot(unpadded), reason: 'the premise');

        for (final spelling in ['$unpadded=', standard]) {
          expect(
              await verifySignedEnvelope(
                  envelope.withEntryMember('signature', spelling),
                  signer: apskOfE()),
              refusedAs(EnvelopeRefusal.malformedEnvelope, kid: kidK()));
        }
        expect(await verifySignedEnvelope(envelope, signer: apskOfE()),
            isA<EnvelopeVerified>(),
            reason: 'the control: the spelling it was signed in verifies');
      });
    });

    group('Given an envelope carrying 1,000 RS256 entries', () {
      late SignedEnvelope thousand;

      setUp(() {
        final one = signedByE([keyR()]).signature.toJson();
        thousand = SignedEnvelope.fromJson({
          'payload': signedByE([keyR()]).payloadB64,
          'signatures': List.filled(1000, one),
        });
      });

      test('when verified, then exactly one public-key verification runs',
          () async {
        final before = envelopeSignatureChecks;

        final result = await verifySignedEnvelope(thousand,
            signer: apskOfE([listedK(), listedR()]));

        expect(result, isA<EnvelopeVerified>());
        expect(envelopeSignatureChecks - before, 1);
      });

      test('when selected, then no public-key verification runs', () {
        final before = envelopeSignatureChecks;

        final selection = selectEnvelopeKey(thousand,
            signer: apskOfE([listedK(), listedR()]));

        expect(selection, isA<EnvelopeKeySelected>());
        expect(envelopeSignatureChecks - before, 0);
      });
    });
  });
}

/// A refusal of [refusal], naming [kid] when given and each of [naming] in
/// its reason.
Matcher refusedAs(EnvelopeRefusal refusal,
    {String? kid, List<String> naming = const []}) {
  var matcher =
      isA<EnvelopeRefused>().having((r) => r.refusal, 'refusal', refusal);
  if (kid != null) matcher = matcher.having((r) => r.kid, 'kid', kid);
  for (final text in naming) {
    matcher = matcher.having((r) => r.reason, 'reason', contains(text));
  }
  return matcher;
}

/// A malformedEnvelope refusal naming no kid.
final Matcher noKidRefusal = isA<EnvelopeRefused>()
    .having((r) => r.refusal, 'refusal', EnvelopeRefusal.malformedEnvelope)
    .having((r) => r.kid, 'kid', isNull);

extension on PublishedApsk {
  /// This `_apsk`'s Atsign and enrollment, holding [value] instead.
  PublishedApsk _withValue(String value) =>
      PublishedApsk(atSign: atSign, enrollmentId: enrollmentId, value: value);
}

/// [value]'s big-endian magnitude.
Uint8List _magnitude(BigInt value) {
  final hex = value.toRadixString(16);
  final even = hex.length.isOdd ? '0$hex' : hex;
  return Uint8List.fromList([
    for (var i = 0; i < even.length; i += 2)
      int.parse(even.substring(i, i + 2), radix: 16)
  ]);
}

/// A DER element of [tag] holding [content].
List<int> _der(int tag, List<int> content) {
  final length = content.length;
  final lengthBytes = length < 0x80
      ? [length]
      : [
          for (var shift = 24; shift >= 0; shift -= 8)
            if (length >> shift != 0 || shift == 0) (length >> shift) & 0xff
        ];
  return [
    tag,
    if (length >= 0x80) 0x80 | lengthBytes.length,
    ...lengthBytes,
    ...content
  ];
}

/// A DER INTEGER holding the non-negative [magnitude].
List<int> _derInteger(Uint8List magnitude) =>
    _der(0x02, [if (magnitude.first & 0x80 != 0) 0, ...magnitude]);
