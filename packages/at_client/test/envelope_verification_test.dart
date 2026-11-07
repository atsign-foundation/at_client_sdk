import 'dart:convert';

import 'package:at_auth/at_auth.dart' show ApskSigningKey, apskAdvertisement;
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
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

import 'test_utils/envelope_signers.dart';

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
        array.replaceAll('"alg":"mldsa65"', '"alg":"slhdsa65"'),
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
}
