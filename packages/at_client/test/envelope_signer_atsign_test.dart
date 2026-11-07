import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show RsaKeyPair, SigningAlgoType, XWingPureDartAlgo;

import 'package:at_client/at_client.dart' show SecretSharingAlgos;
import 'package:at_client/at_client_mixins.dart'
    show
        AtClientEnvelopeSigner,
        KeyPackage,
        KeyPackageStatus,
        PackageKey,
        verifyAdvertisedKeyPackage;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyAdvertisement;
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart'
    show ApkamSignedAdvertisedKeys;
import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart'
    show LinkVoucher;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException, AtValue;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/envelope_signers.dart';
import 'test_utils/envelope_tamper.dart';
import 'test_utils/mocks.dart' show MockAtClient;

/// Catalogue: features/at_client/envelope_signer_atsign.feature
void main() {
  const alice = '@alice';
  const e = 'enroll-e';
  late Map<String, String> remoteData;
  late SigningClient ofE;

  setUp(() async {
    remoteData = {};
    ofE = await signingClient(alice, e, remoteData);
  });

  Map<String, Object?> headerOf(EnvelopeSignature entry) =>
      (jsonDecode(unb64u(entry.protected)) as Map).cast<String, Object?>();

  test(
      "Every envelope at_client signs names its signer's Atsign: an "
      'application payload through EnvelopeSigning.wrapAndSign', () async {
    final envelope = await ofE.signer.wrapAndSign({'result': 1});

    for (final entry in envelope.signatures) {
      expect(headerOf(entry)['iss'], alice);
    }
    expect(envelope.signerAtSign, alice);
  });

  test(
      "Every envelope at_client signs names its signer's Atsign: a chain "
      'link through PqSigningChain.signChainLink', () async {
    final link = SignedEnvelope.fromJson(await LinkVoucher.chain(
        key: ofE.key,
        atSign: alice,
        enrollmentId: e,
        keysWalked: const []).sign({'v': 2}));

    expect(link.signatures.map((s) => s.iss).toSet(), {alice});
    expect(link.signerAtSign, alice);
  });

  test(
      "An application envelope's header names the Atsign after the key and "
      'before the enrollment', () async {
    final envelope = await ofE.signer.wrapAndSign({'result': 1});

    for (final entry in envelope.signatures) {
      final header = headerOf(entry);
      expect(header.keys.toList(), ['alg', 'typ', 'kid', 'iss', 'enid', 'v']);
      expect(header['v'], 1);
    }
  });

  group('Given a client whose current Atsign is spelt "@Alice"', () {
    test('when it signs, then iss is "@alice"', () async {
      final spelt = await signingClient('@Alice', e, remoteData);

      final envelope = await spelt.signer.wrapAndSign({'result': 1});

      expect(headerOf(envelope.signature)['iss'], alice);
    });
  });

  group('read with SignedEnvelope.fromJson', () {
    late SignedEnvelope twoEntries;
    late List<ApkamSigningKeys> keys;

    setUp(() async {
      final rsa = RsaKeyPair.generate();
      keys = [
        ofE.key,
        ApkamSigningKeys(
            algorithm: SigningAlgoType.rsa2048,
            publicKey: rsa.atPublicKey.publicKey,
            privateKey: rsa.atPrivateKey.privateKey),
      ];
      twoEntries = signEnvelope({'result': 1},
          keys: keys, type: EnvelopeType.app, atSign: alice, enrollmentId: e);
    });

    /// [twoEntries] with its RS256 entry's header passed through [edit].
    Map<String, Object?> withSecondEntry(
            Map<String, Object?> Function(Map<String, Object?>) edit) =>
        resigned(twoEntries, keys,
                (header) => header['alg'] == 'RS256' ? edit(header) : header)
            .toJson();

    for (final (other, edit) in [
      ('naming iss "@bob"', (Map<String, Object?> h) => h..['iss'] = '@bob'),
      ('naming no iss', (Map<String, Object?> h) => h..remove('iss')),
    ]) {
      test(
          'An envelope whose entries disagree about the Atsign is refused when '
          'read: one entry naming iss "@alice" and another $other', () {
        expect(
            () => SignedEnvelope.fromJson(withSecondEntry(edit)),
            throwsA(isA<AtSigningVerificationException>()
                .having((x) => x.message, 'message', contains('"@alice"'))
                .having((x) => x.message, 'message',
                    contains(other.contains('@bob') ? '"@bob"' : 'none'))));
      });
    }

    group('Given an envelope whose entries name "@alice" and "@Alice"', () {
      test(
          'when it is read with SignedEnvelope.fromJson, then it is accepted '
          'as one signer', () {
        final envelope = SignedEnvelope.fromJson(
            withSecondEntry((h) => h..['iss'] = '@Alice'));

        expect(envelope.signerAtSign, alice);
        expect(envelope.signatures, hasLength(2),
            reason: 'the control: both entries are still there');
      });
    });
  });

  group('verifying', () {
    const bob = '@bob';
    late AtClientEnvelopeSigner ofBob;
    late SignedEnvelope envelope;

    setUp(() async {
      ofBob = readerOf(bob, 'enroll-b', remoteData);
      envelope = await ofE.signer.wrapAndSign({'result': 1});
      // NOTE: @bob's enrollment E lists K too, so the claim is the only
      // thing that tells the two Atsigns apart.
      remoteData[apskUri(bob, e)] = ofE.apsk;
    });

    Future<AtValue> apskRead(AtClientEnvelopeSigner signer) =>
        (signer.atClient as MockAtClient)
            .get(any(), getRequestOptions: any(named: 'getRequestOptions'));

    test('verifyEnvelopeSignature refuses an envelope naming another Atsign',
        () async {
      await expectLater(
          ofBob.verifyEnvelopeSignature(envelope, signerAtSign: bob),
          throwsA(isA<AtSigningVerificationException>()
              .having((x) => x.message, 'message', contains('"@alice"'))
              .having((x) => x.message, 'message', contains('"@bob"'))));
      verifyNever(() => apskRead(ofBob));

      // NOTE: positive control — verified as @alice's, the same envelope
      // fetches its _apsk and verifies.
      await ofBob.verifyEnvelopeSignature(envelope, signerAtSign: alice);
      verify(() => apskRead(ofBob)).called(1);
    });

    test('verifyEnvelopeSignature accepts an envelope that names no Atsign',
        () async {
      final unnamed = claimless(envelope, [ofE.key]);
      expect(unnamed.signerAtSign, isNull);

      await ofBob.verifyEnvelopeSignature(unnamed, signerAtSign: alice);
    });

    group("at_client's own verifiers", () {
      late Uint8List encapsulationKey;

      setUp(() async => encapsulationKey =
          (await XWingPureDartAlgo.instance.generateKeyPair()).publicKey);

      Future<SignedEnvelope> nskeyAdvertisement() => ofE.signer.wrapAndSign(
          NskeyAdvertisement.single(
                  publicKey: encapsulationKey, alg: SecretSharingAlgos.xWing)
              .toPayload(),
          type: EnvelopeType.nskeyRing);

      Future<SignedEnvelope> keyPackage() => ofE.signer.wrapAndSign(
          KeyPackage.payloadFor(createdAt: DateTime.utc(2026), keys: [
            PackageKey(
                use: SecretSharingAlgos.useEnc,
                alg: SecretSharingAlgos.xWing,
                pub: base64Encode(encapsulationKey))
          ]),
          type: EnvelopeType.keyPackage);

      Future<KeyPackageStatus> keyPackageStatus(
              SignedEnvelope envelope, String signerAtSign) async =>
          (await verifyAdvertisedKeyPackage(envelope.toJson(),
                  signer: ofBob, signerAtSign: signerAtSign, enrollmentId: e))
              .$2;

      test(
          "at_client's own verifiers refuse a document naming another Atsign: "
          'an nskey advertisement through ApkamSignedAdvertisedKeys.verify',
          () async {
        final advertised = jsonEncode((await nskeyAdvertisement()).toJson());

        await expectLater(
            ApkamSignedAdvertisedKeys(ofBob.atClient).verify(bob, advertised),
            throwsA(isA<AtSigningVerificationException>()
                .having((x) => x.message, 'message', contains('"@alice"'))
                .having((x) => x.message, 'message', contains('"@bob"'))));
      });

      test(
          "at_client's own verifiers refuse a document naming another Atsign: "
          'a key package through verifyAdvertisedKeyPackage', () async {
        final envelope = await keyPackage();

        expect(
            await keyPackageStatus(envelope, bob), KeyPackageStatus.rejected);
        expect(
            await keyPackageStatus(envelope, alice), KeyPackageStatus.present,
            reason: 'the control: the same package, checked as @alice\'s');
      });

      test(
          "at_client's own verifiers accept a document that names no Atsign: "
          'an nskey advertisement through ApkamSignedAdvertisedKeys.verify',
          () async {
        final unnamed = claimless(await nskeyAdvertisement(), [ofE.key]);

        final advertisement = await ApkamSignedAdvertisedKeys(ofBob.atClient)
            .verify(alice, jsonEncode(unnamed.toJson()));

        expect(advertisement.keys.single.pub, base64Encode(encapsulationKey));
      });

      test(
          "at_client's own verifiers accept a document that names no Atsign: "
          'a key package through verifyAdvertisedKeyPackage', () async {
        final unnamed = claimless(await keyPackage(), [ofE.key]);

        expect(
            await keyPackageStatus(unnamed, alice), KeyPackageStatus.present);
      });
    });

    group('Given an envelope whose iss is "@Alice"', () {
      test(
          'when verifyEnvelopeSignature checks it with signerAtSign "ALICE", '
          'then it verifies', () async {
        final spelt = resigned(
            envelope, [ofE.key], (header) => header..['iss'] = '@Alice');

        await ofBob.verifyEnvelopeSignature(spelt, signerAtSign: 'ALICE');
      });
    });

    group('Given an envelope whose iss is not an Atsign', () {
      test(
          'when verifyEnvelopeSignature checks it, then it throws '
          'AtSigningVerificationException naming the claim', () async {
        final notAnAtsign = resigned(
            envelope, [ofE.key], (header) => header..['iss'] = '@al ice');

        await expectLater(
            ofBob.verifyEnvelopeSignature(notAnAtsign, signerAtSign: alice),
            throwsA(isA<AtSigningVerificationException>()
                .having((x) => x.message, 'message', contains('"@al ice"'))));
      });
    });
  });
}
